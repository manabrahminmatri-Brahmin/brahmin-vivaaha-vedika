const functions = require("firebase-functions");
const Razorpay = require("razorpay");

let _cloudinary;
function getCloudinary() {
  if (!_cloudinary) {
    _cloudinary = require("cloudinary").v2;
    _cloudinary.config({
      cloud_name: cloudName,
      api_key: apiKey,
      api_secret: apiSecret,
    });
  }
  return _cloudinary;
}
const crypto = require("crypto");
const admin = require("firebase-admin");

// Initialize Firebase Admin (index.js may have initialized already)
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

const { createRateLimiter, MATRIMONY_LIMITS } = require("./src/rate_limit");
const {
  assertValidRequestDocId,
  normalizeAccessStatus,
  applyTransitionAudit,
  notifyRequesterOutcome,
} = require("./src/access_request_lifecycle");
const rateLimiter = createRateLimiter(db, admin);

const DENY_RESEND_COOLDOWN_MS = 24 * 60 * 60 * 1000;
const REVOKE_RESEND_COOLDOWN_MS = 60 * 60 * 1000;

function parseDeniedOrRevokedAtMs(row) {
  const raw =
    row?.deniedAt ||
    row?.denied_at ||
    row?.revokedAt ||
    row?.revoked_at ||
    row?.responded_at;
  if (!raw) return null;
  if (typeof raw === "string") {
    const ms = Date.parse(raw);
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof raw?.toMillis === "function") {
    return raw.toMillis();
  }
  if (raw instanceof Date) return raw.getTime();
  return null;
}

function assertPrivacyRequestBinding(requestId, requesterId, ownerId) {
  const expected = `${requesterId}_${ownerId}`;
  if (requestId !== expected) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Request document binding mismatch."
    );
  }
}

// Gen-1 HTTPS + Firestore triggers: match Firestore database region (asia-south1).
const fnAsia = functions.region("asia-south1");

// Credentials: functions/.env (deploy) or firebase functions:secrets:set (production).
// Legacy functions.config() removed — Runtime Config shuts down March 2027.
const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
const apiKey = process.env.CLOUDINARY_API_KEY;
const apiSecret = process.env.CLOUDINARY_API_SECRET;

const razorpayKeyId = process.env.RAZORPAY_KEY_ID;
const razorpaySecret = process.env.RAZORPAY_SECRET;
const razorpayWebhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;

function isRazorpayWebhookSecretMisconfigured() {
  const w = (razorpayWebhookSecret || "").toString().trim();
  const k = (razorpayKeyId || "").toString().trim();
  if (!w || w.length < 8) return "missing_or_short";
  if (k && w === k) return "equals_key_id";
  return "";
}

async function logRazorpayWebhookError({
  eventType = "unknown",
  message = "",
  stack = "",
  details = {},
}) {
  try {
    await db.collection("webhook_errors").add({
      gateway: "razorpay",
      eventType: String(eventType).slice(0, 200),
      message: String(message || "").slice(0, 2000),
      stack: String(stack || "").slice(0, 4000),
      details: typeof details === "object" && details ? details : {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("logRazorpayWebhookError failed:", e?.message || e);
  }
}

// ─────────────────────────────────────────────
// FUNCTION 1: Get signed upload signature
// Flutter calls this before uploading a photo
// ─────────────────────────────────────────────
exports.getCloudinarySignature = fnAsia
  .runWith({ secrets: ['CLOUDINARY_CLOUD_NAME', 'CLOUDINARY_API_KEY', 'CLOUDINARY_API_SECRET'] })
  .https.onCall(async (data, context) => {
  // Block unauthenticated calls
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in to upload photos."
    );
  }

  const uid       = context.auth.uid;
  const timestamp = Math.round(new Date().getTime() / 1000);

  // Each user gets exactly ONE photo slot — overwrite on re-upload
  const publicId = `profile_photos/${uid}/profile`;
  const folder   = `profile_photos/${uid}`;

  // Sign the upload params — api_secret never leaves this function
  const signature = getCloudinary().utils.api_sign_request(
    {
      timestamp,
      public_id:      publicId,
      folder,
      overwrite:      true,
      // Server-side resize: crop to 800x800, 85% quality
      eager: "c_fill,w_800,h_800,q_85,f_jpg",
    },
    apiSecret
  );

  return {
    signature,
    timestamp,
    api_key:    apiKey,
    cloud_name: cloudName,
    public_id:  publicId,
    folder,
  };
});

// ─────────────────────────────────────────────
// FUNCTION 2: Delete user's profile photo
// Flutter calls this when user taps Remove
// ─────────────────────────────────────────────
exports.deleteCloudinaryPhoto = fnAsia
  .runWith({ secrets: ['CLOUDINARY_CLOUD_NAME', 'CLOUDINARY_API_KEY', 'CLOUDINARY_API_SECRET'] })
  .https.onCall(async (data, context) => {
  // Block unauthenticated calls
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in to delete photos."
    );
  }

  const uid      = context.auth.uid;
  // User can ONLY delete their own photo — uid is from verified auth token
  const publicId = `profile_photos/${uid}/profile`;

  try {
    const result = await getCloudinary().uploader.destroy(publicId, {
      invalidate: true, // purge from Cloudinary CDN cache immediately
    });
    return { success: true, result };
  } catch (e) {
    throw new functions.https.HttpsError("internal", `Delete failed: ${e.message}`);
  }
});

// ─────────────────────────────────────────────
// RAZORPAY PAYMENT FUNCTIONS
// ─────────────────────────────────────────────

// Initialize Razorpay instance (lazy load)
let razorpayInstance = null;
function getRazorpayInstance() {
  if (!razorpayKeyId || !razorpaySecret) {
    throw new Error("Razorpay credentials are missing on server");
  }
  if (!razorpayInstance) {
    razorpayInstance = new Razorpay({
      key_id: razorpayKeyId,
      key_secret: razorpaySecret,
    });
  }
  return razorpayInstance;
}

/**
 * Resolve user doc ref for apps that store user docs by non-auth IDs.
 * Priority:
 *  1. /users/{authUid}
 *  2. /users where auth_uid == authUid
 */
async function resolveUserRefByAuthUid(authUid) {
  const directRef = db.collection("users").doc(authUid);
  const directSnap = await directRef.get();
  if (directSnap.exists) {
    return directRef;
  }

  const linked = await db
    .collection("users")
    .where("auth_uid", "==", authUid)
    .limit(1)
    .get();

  if (!linked.empty) {
    return linked.docs[0].ref;
  }

  return null;
}

async function resolveCallerProfileRef(context, payloadRequesterId = "") {
  const callerUid = (context.auth?.uid || "").toString().trim();
  if (!callerUid) return null;

  // Preferred path: resolve by auth_uid mapping.
  const byAuth = await resolveUserRefByAuthUid(callerUid);
  if (byAuth) return byAuth;

  // Recovery path: if client sent requester profile doc id, bind it safely.
  const fallbackId = (payloadRequesterId || "").toString().trim();
  if (!fallbackId) {
    console.warn("resolveCallerProfileRef: no fallback requesterId", { callerUid });
    return null;
  }
  console.warn("resolveCallerProfileRef: using fallback requesterId", {
    callerUid,
    payloadRequesterId: fallbackId,
  });
  let ref = db.collection("users").doc(fallbackId);
  let snap = await ref.get();
  if (!snap.exists) {
    // Legacy payload may still carry auth UID — resolve it to profile doc id.
    const byAuth = await db
      .collection("users")
      .where("auth_uid", "==", fallbackId)
      .limit(1)
      .get();
    if (byAuth.empty) {
      console.warn("resolveCallerProfileRef: fallback did not match any user", {
        callerUid,
        payloadRequesterId: fallbackId,
      });
      return null;
    }
    ref = byAuth.docs[0].ref;
    snap = byAuth.docs[0];
  }

  const row = snap.data() || {};
  const existingAuth = (row.auth_uid || "").toString().trim();
  if (existingAuth && existingAuth !== callerUid) {
    const normalizeMobile = (v) =>
      (v || "").toString().replace(/\D/g, "").replace(/^91/, "");
    const tokenPhone = normalizeMobile(context.auth?.token?.phone_number || "");
    const docPhone = normalizeMobile(row.mobile_number || row.mobileNumber || "");
    const samePhone =
      tokenPhone.length >= 10 && docPhone.length >= 10 && tokenPhone === docPhone;
    if (!samePhone) {
      // Doc belongs to some other auth UID and cannot be safely rebound.
      console.warn("resolveCallerProfileRef: auth mismatch", {
        callerUid,
        docId: ref.id,
        existingAuth,
        tokenPhoneSuffix: tokenPhone.slice(-4),
        docPhoneSuffix: docPhone.slice(-4),
      });
      return null;
    }
    console.warn("resolveCallerProfileRef: rebinding auth_uid by phone match", {
      callerUid,
      docId: ref.id,
      existingAuth,
    });
    await ref.set(
      {
        auth_uid: callerUid,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  // Safe self-heal: write missing auth_uid binding.
  if (!existingAuth) {
    await ref.set(
      {
        auth_uid: callerUid,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
  return ref;
}

function parseRequestId(requestId) {
  const raw = (requestId || "").toString().trim();
  if (!raw || !raw.includes("_")) return null;
  const parts = raw.split("_");
  if (parts.length < 2) return null;
  const requesterId = (parts[0] || "").trim();
  const ownerId = parts.slice(1).join("_").trim();
  if (!requesterId || !ownerId) return null;
  return { requesterId, ownerId };
}

/** Callable payloads may use snake_case (Flutter) or camelCase. */
function readAccessRequestPayload(data) {
  const d = data || {};
  return {
    requesterId: (d.requesterId || d.requester_id || "").toString().trim(),
    ownerId: (d.ownerId || d.owner_id || "").toString().trim(),
    requestId: (d.requestId || d.request_id || "").toString().trim(),
    forceResend: d.forceResend === true || d.force_resend === true,
  };
}

async function resolveAccessRequestDocRef(collectionName, opts) {
  const requestId = (opts.requestId || "").toString().trim();
  const requesterId = (opts.requesterId || "").toString().trim();
  const ownerId = (opts.ownerId || "").toString().trim();
  const authUid = (opts.authUid || "").toString().trim();
  const col = db.collection(collectionName);

  if (requestId) {
    const direct = await col.doc(requestId).get();
    if (direct.exists) {
      return { ref: direct.ref, snap: direct, requestId: direct.id };
    }
  }

  const composite =
    requesterId && ownerId ? `${requesterId}_${ownerId}` : "";
  if (composite && composite !== requestId) {
    const byComposite = await col.doc(composite).get();
    if (byComposite.exists) {
      return { ref: byComposite.ref, snap: byComposite, requestId: byComposite.id };
    }
  }

  if (requesterId && ownerId) {
    const byFields = await col
      .where("requester_id", "==", requesterId)
      .where("owner_id", "==", ownerId)
      .limit(1)
      .get();
    if (!byFields.empty) {
      const doc = byFields.docs[0];
      return { ref: doc.ref, snap: doc, requestId: doc.id };
    }
  }

  if (authUid && ownerId) {
    const byLegacy = await col
      .where("requester_auth_uid", "==", authUid)
      .where("owner_id", "==", ownerId)
      .limit(1)
      .get();
    if (!byLegacy.empty) {
      const doc = byLegacy.docs[0];
      return { ref: doc.ref, snap: doc, requestId: doc.id };
    }
  }

  return null;
}

function parseIsoDateToMillis(value) {
  if (typeof value !== "string" || value.trim().length === 0) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

function parseDateLikeToMillis(value) {
  if (value == null) return null;
  if (typeof value === "string") return parseIsoDateToMillis(value);
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value?.toMillis === "function") {
    const ms = value.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

/**
 * Idempotent premium entitlement application.
 * Ensures the same Razorpay payment cannot grant premium twice.
 */
async function applyPremiumEntitlementIfNeeded({
  orderId,
  paymentId,
  uid,
  amountPaise,
  planDays,
  source,
}) {
  if (!orderId || !paymentId || !uid) {
    return { applied: false, reason: "missing_required_fields" };
  }

  const paymentRef = db.collection("payments").doc(orderId);
  const paymentEventRef = db.collection("payment_events").doc(paymentId);
  const userRef = await resolveUserRefByAuthUid(uid);
  if (!userRef) {
    const alertRef = db.collection("payment_alerts").doc(`${orderId}_${paymentId}`);
    await alertRef.set(
      {
        orderId,
        paymentId,
        uid,
        source,
        reason: "user_profile_not_found",
        requiresManualAction: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await paymentRef.set(
      {
        premiumApplyStatus: "failed_user_profile_not_found",
        premiumApplySource: source,
        premiumApplyPaymentId: paymentId,
        premiumApplyUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { applied: false, reason: "user_profile_not_found" };
  }

  // Safety clamp prevents accidental extreme extension while preserving renewals.
  const normalizedPlanDays = Number.isFinite(planDays) ? Math.trunc(planDays) : 0;
  const validPlanDays = normalizedPlanDays > 0 ? Math.min(normalizedPlanDays, 3650) : 30;
  const amountPaid = Number.isFinite(amountPaise) ? amountPaise / 100 : 0;

  return db.runTransaction(async (tx) => {
    let userSnap = null;
    const [paymentSnap, paymentEventSnap] = await Promise.all([
      tx.get(paymentRef),
      tx.get(paymentEventRef),
    ]);
    if (userRef) {
      userSnap = await tx.get(userRef);
    }

    const alreadyAppliedByPaymentDoc =
      paymentSnap.exists &&
      paymentSnap.data() &&
      paymentSnap.data().premiumAppliedPaymentId === paymentId;

    if (paymentEventSnap.exists || alreadyAppliedByPaymentDoc) {
      return { applied: false, reason: "duplicate_payment_event" };
    }

    const now = admin.firestore.Timestamp.now();
    const nowMs = now.toMillis();
    let renewalBaseMs = nowMs;
    let premiumSinceIso = now.toDate().toISOString();
    if (userSnap && userSnap.exists) {
      const userData = userSnap.data() || {};
      const currentExpiryCandidates = [
        parseDateLikeToMillis(userData.membership_expiry_date),
        parseDateLikeToMillis(userData.membership_json?.expiryDate),
      ].filter((v) => v != null);
      if (currentExpiryCandidates.length > 0) {
        const latestKnownExpiryMs = Math.max(...currentExpiryCandidates);
        if (latestKnownExpiryMs > renewalBaseMs) {
          renewalBaseMs = latestKnownExpiryMs;
        }
      }
      const existingPremiumSinceMs = parseDateLikeToMillis(
        userData.premiumSince ?? userData.membership_json?.startDate
      );
      if (existingPremiumSinceMs != null) {
        premiumSinceIso = new Date(existingPremiumSinceMs).toISOString();
      }
    }
    const expiryDate = admin.firestore.Timestamp.fromDate(
      new Date(renewalBaseMs + validPlanDays * 24 * 60 * 60 * 1000)
    );

    tx.set(
      paymentRef,
      {
        premiumAppliedPaymentId: paymentId,
        premiumAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
        premiumApplySource: source,
        premiumApplyStatus: "applied",
        premiumApplyUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(paymentEventRef, {
      paymentId,
      orderId,
      uid,
      source,
      amountPaise: Number.isFinite(amountPaise) ? amountPaise : 0,
      planDays: validPlanDays,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(
      userRef,
      {
        isPremium: true,
        premiumSince: premiumSinceIso,
        lastPaymentId: paymentId,
        lastOrderId: orderId,
        membership_tier: "platinum",
        membership_status: "platinum",
        membership_json: {
          tier: "platinum",
          startDate: premiumSinceIso,
          expiryDate: expiryDate.toDate().toISOString(),
          transactionId: paymentId,
          amountPaid: amountPaid,
          planDays: validPlanDays,
        },
        membership_expiry_date: expiryDate.toDate().toISOString(),
        updated_at: now,
      },
      { merge: true }
    );

    const notificationRef = db.collection("notifications").doc();
    tx.set(notificationRef, {
      userId: uid,
      type: "payment_success",
      title: "Payment Successful",
      body: `Your payment of ₹${amountPaid} was successful. You are now a premium member!`,
      data: {
        orderId: orderId,
        paymentId: paymentId,
        amount: Number.isFinite(amountPaise) ? amountPaise : 0,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    return { applied: true, reason: "applied" };
  });
}

/**
 * Create a Razorpay order
 * Called by Flutter before opening checkout
 */
exports.createRazorpayOrder = fnAsia
  .runWith({ secrets: ['RAZORPAY_KEY_ID', 'RAZORPAY_SECRET'] })
  .https.onCall(async (data, context) => {
  // Block unauthenticated calls
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in to make a payment."
    );
  }

  const { amount, currency = "INR", receipt, notes = {} } = data;
  const uid = context.auth.uid;

  if (!razorpayKeyId || !razorpaySecret) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Payment gateway is not configured. Please contact support."
    );
  }

  // Validate amount
  if (!amount || amount < 100) { // Minimum 100 paise = ₹1
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Amount must be at least ₹1 (100 paise)"
    );
  }

  try {
    const fallbackReceipt = `rcpt_${uid.substring(0, 8)}_${Date.now()}`;
    const rawReceipt = typeof receipt === "string" && receipt.trim().length > 0
      ? receipt.trim()
      : fallbackReceipt;
    const safeReceipt =
      rawReceipt.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 40) ||
      fallbackReceipt.slice(0, 40);

    // Create order in Razorpay
    const orderOptions = {
      amount: Math.round(amount), // Amount in paise
      currency: currency,
      receipt: safeReceipt,
      notes: {
        ...notes,
        firebaseUid: uid,
        createdAt: new Date().toISOString(),
      },
    };

    const order = await getRazorpayInstance().orders.create(orderOptions);

    // Store pending order in Firestore
    const profileId = String(notes?.userDocId || notes?.user_doc_id || "").trim();
    const paymentRow = {
      orderId: order.id,
      uid: uid,
      amount: amount,
      currency: currency,
      status: "created",
      receipt: order.receipt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      notes: notes,
    };
    if (profileId) {
      paymentRow.profile_id = profileId;
    }
    await db.collection("payments").doc(order.id).set(paymentRow);

    // Return order details to client (only non-sensitive data)
    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      keyId: razorpayKeyId, // Public key only
    };
  } catch (error) {
    console.error("Error creating Razorpay order:", error);
    const safeErrorMessage =
      (error && (error.description || error.message || error.error?.description)) ||
      String(error) ||
      "Unknown Razorpay error";
    throw new functions.https.HttpsError(
      "internal",
      `Failed to create order: ${safeErrorMessage}`
    );
  }
});

/**
 * Verify Razorpay payment signature
 * Called by Flutter after payment completes
 */
exports.verifyRazorpayPayment = fnAsia
  .runWith({ secrets: ['RAZORPAY_KEY_ID', 'RAZORPAY_SECRET'] })
  .https.onCall(async (data, context) => {
  // Block unauthenticated calls
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in to verify payment."
    );
  }

  const { orderId, paymentId, signature } = data;
  const uid = context.auth.uid;

  if (!orderId || !paymentId || !signature) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing required payment verification data"
    );
  }

  try {
    // Verify signature
    const body = orderId + "|" + paymentId;
    const expectedSignature = crypto
      .createHmac("sha256", razorpaySecret)
      .update(body)
      .digest("hex");

    const isValid = signature === expectedSignature;

    if (!isValid) {
      // Log suspicious activity
      console.warn(`Invalid payment signature attempt by user ${uid}`);
      throw new functions.https.HttpsError(
        "permission-denied",
        "Invalid payment signature"
      );
    }

    // Fetch payment details from Razorpay
    const payment = await getRazorpayInstance().payments.fetch(paymentId);

    // Update payment record in Firestore
    const paymentRef = db.collection("payments").doc(orderId);
    await paymentRef.update({
      paymentId: paymentId,
      signature: signature,
      status: payment.status, // 'captured', 'failed', etc.
      method: payment.method,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      verified: true,
    });

    // If payment captured, apply premium in an idempotent way.
    if (payment.status === "captured") {
      const planDays = Number(payment.notes?.planDays || 30);
      const applyResult = await applyPremiumEntitlementIfNeeded({
        orderId,
        paymentId,
        uid,
        amountPaise: payment.amount,
        planDays,
        source: "verify_callable",
      });
      if (!applyResult.applied) {
        if (applyResult.reason === "user_profile_not_found") {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Payment captured, but premium activation failed: user profile mapping missing."
          );
        }
        console.log(
          `Skipping duplicate premium application for paymentId=${paymentId}, reason=${applyResult.reason}`
        );
      }
    }

    return {
      success: true,
      status: payment.status,
      amount: payment.amount,
      method: payment.method,
    };
  } catch (error) {
    console.error("Error verifying payment:", error);
    throw new functions.https.HttpsError(
      "internal",
      `Payment verification failed: ${error.message}`
    );
  }
});

/**
 * Razorpay webhook handler
 * Called by Razorpay for payment events
 */
exports.razorpayWebhook = fnAsia
  .runWith({
    secrets: ["RAZORPAY_WEBHOOK_SECRET", "RAZORPAY_KEY_ID", "RAZORPAY_SECRET"],
  })
  .https.onRequest(async (req, res) => {
  let webhookEventType = "unknown";
  // Only accept POST requests
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const misCfg = isRazorpayWebhookSecretMisconfigured();
  if (misCfg) {
    const msg = `RAZORPAY_WEBHOOK_SECRET misconfigured (${misCfg}). Use the signing secret from Razorpay Dashboard → Settings → Webhooks (not the Key ID).`;
    console.error(msg);
    await logRazorpayWebhookError({
      eventType: "config",
      message: msg,
      details: { misCfg },
    });
    res.status(503).send("Webhook misconfigured");
    return;
  }

  const signature = req.headers["x-razorpay-signature"];
  if (!signature) {
    res.status(400).send("Missing signature");
    return;
  }

  // Verify webhook signature
  const body = JSON.stringify(req.body);
  const expectedSignature = crypto
    .createHmac("sha256", razorpayWebhookSecret)
    .update(body)
    .digest("hex");

  if (signature !== expectedSignature) {
    console.warn("Invalid webhook signature");
    await logRazorpayWebhookError({
      eventType: "signature_invalid",
      message: "x-razorpay-signature HMAC mismatch",
      details: { hasBody: Boolean(req.body) },
    });
    res.status(400).send("Invalid signature");
    return;
  }

  try {
    const event = req.body;
    const eventType = event.event;
    webhookEventType = eventType || "unknown";
    const payload = event.payload || {};

    console.log(`Received Razorpay webhook: ${eventType}`);

    // Handle different event types
    switch (eventType) {
      case "payment.captured":
        await handlePaymentCaptured(payload.payment.entity);
        break;
      case "payment.failed":
        await handlePaymentFailed(payload.payment.entity);
        break;
      case "order.paid":
        await handleOrderPaid(payload.order.entity);
        break;
      case "refund.processed":
        if (payload.refund && payload.refund.entity) {
          await handleRefundProcessed(payload.refund.entity);
        } else {
          console.warn("refund.processed: missing payload.refund.entity");
        }
        break;
      case "refund.failed":
        if (payload.refund && payload.refund.entity) {
          await handleRefundFailed(payload.refund.entity);
        }
        break;
      default:
        console.log(`Unhandled event type: ${eventType}`);
    }

    res.status(200).send("OK");
  } catch (error) {
    console.error("Error processing webhook:", error);
    await logRazorpayWebhookError({
      eventType: webhookEventType,
      message: error?.message || String(error),
      stack: error?.stack || "",
      details: { phase: "handler" },
    });
    res.status(500).send("Internal Server Error");
  }
});

// Webhook helper functions
async function handlePaymentCaptured(payment) {
  const orderId = payment.order_id;
  if (!orderId) return;

  const paymentRef = db.collection("payments").doc(orderId);
  const paymentDoc = await paymentRef.get();

  if (paymentDoc.exists) {
    await paymentRef.update({
      status: "captured",
      capturedAt: admin.firestore.FieldValue.serverTimestamp(),
      method: payment.method,
      email: payment.email,
      contact: payment.contact,
    });

    // Idempotent premium update (handles duplicate webhook events safely)
    const data = paymentDoc.data();
    if (data && data.uid) {
      const planDays = Number(data.notes?.planDays || 30);
      const applyResult = await applyPremiumEntitlementIfNeeded({
        orderId,
        paymentId: payment.id,
        uid: data.uid,
        amountPaise: payment.amount,
        planDays,
        source: "razorpay_webhook_payment_captured",
      });
      if (!applyResult.applied) {
        console.log(
          `Skipping duplicate premium application in webhook for paymentId=${payment.id}, reason=${applyResult.reason}`
        );
      }
    }
  }
}

async function handlePaymentFailed(payment) {
  const orderId = payment.order_id;
  if (!orderId) return;

  const paymentRef = db.collection("payments").doc(orderId);
  await paymentRef.set({
    status: "failed",
    failedAt: admin.firestore.FieldValue.serverTimestamp(),
    paymentId: payment.id || null,
    orderId: orderId,
    method: payment.method || null,
    email: payment.email || null,
    contact: payment.contact || null,
    errorCode: payment.error_code,
    errorDescription: payment.error_description,
  }, { merge: true });

  // Failed cases go to admin review queue; success path never needs admin intervention.
  const paymentSnap = await paymentRef.get();
  const paymentData = paymentSnap.exists ? (paymentSnap.data() || {}) : {};
  const uid = (paymentData.uid || payment.notes?.firebaseUid || "").toString();
  const userDocId = String(
    paymentData.notes?.userDocId || paymentData.notes?.user_doc_id || ""
  ).trim();

  await db.collection("payment_requests").doc(`${orderId}_failed`).set({
    orderId: orderId,
    paymentId: payment.id || "",
    user_id: uid,
    userDocId: userDocId || null,
    userId: uid,
    authUid: uid,
    amount: Number.isFinite(payment.amount) ? payment.amount / 100 : 0,
    currency: payment.currency || "INR",
    gateway: "razorpay",
    status: "failed_needs_admin_review",
    errorCode: payment.error_code || "",
    errorDescription: payment.error_description || "Payment failed",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    source: "razorpay_webhook_payment_failed",
  }, { merge: true });
}

async function handleOrderPaid(order) {
  const orderId = order.id;
  const paymentRef = db.collection("payments").doc(orderId);
  
  await paymentRef.update({
    status: "paid",
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    amountPaid: order.amount_paid,
  });
}

/**
 * Refund confirmed — revoke premium tied to the original Razorpay order (best-effort).
 * Requires RAZORPAY_SECRET on the webhook function to fetch payment → order_id.
 */
async function handleRefundProcessed(refund) {
  const paymentId = (refund.payment_id || "").toString().trim();
  const refundId = (refund.id || "").toString().trim();
  if (!paymentId) {
    console.warn("handleRefundProcessed: missing payment_id");
    return;
  }
  if (!razorpaySecret) {
    console.warn("handleRefundProcessed: RAZORPAY_SECRET not set; cannot resolve order");
    return;
  }
  let orderId = "";
  try {
    const pay = await getRazorpayInstance().payments.fetch(paymentId);
    orderId = (pay.order_id || "").toString().trim();
  } catch (e) {
    console.error("handleRefundProcessed: payments.fetch failed", e?.message || e);
    await logRazorpayWebhookError({
      eventType: "refund.processed",
      message: `payments.fetch failed: ${e?.message || e}`,
      details: { paymentId, refundId },
    });
    return;
  }
  if (!orderId) {
    console.warn("handleRefundProcessed: no order_id on payment", paymentId);
    return;
  }

  const paymentRef = db.collection("payments").doc(orderId);
  const snap = await paymentRef.get();
  const uid = snap.exists ? (snap.data().uid || "").toString().trim() : "";

  await paymentRef.set(
    {
      refundStatus: "processed",
      refundId: refundId || null,
      refundAmountPaise: Number.isFinite(refund.amount) ? refund.amount : null,
      refundPaymentId: paymentId,
      refundedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  const userRef = uid ? await resolveUserRefByAuthUid(uid) : null;
  if (!userRef) {
    console.warn("handleRefundProcessed: no user doc for uid", uid, "order", orderId);
    await logRazorpayWebhookError({
      eventType: "refund.processed",
      message: "user_profile_not_found_for_refund_revoke",
      details: { orderId, paymentId, refundId, uid },
    });
    return;
  }

  await userRef.set(
    {
      isPremium: false,
      membership_tier: "free",
      membership_status: "free",
      membership_expiry_date: admin.firestore.FieldValue.delete(),
      membership_json: {
        tier: "free",
        startDate: null,
        expiryDate: null,
        transactionId: null,
        amountPaid: 0,
        planDays: 0,
      },
      lastRefundPaymentId: paymentId,
      lastRefundId: refundId || null,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  console.log("handleRefundProcessed: premium revoked for uid", uid, "order", orderId);
}

async function handleRefundFailed(refund) {
  const paymentId = (refund.payment_id || "").toString().trim();
  const orderIdGuess = (refund.notes?.orderId || "").toString().trim();
  await logRazorpayWebhookError({
    eventType: "refund.failed",
    message: (refund.error_description || refund.error_reason || "refund failed").toString(),
    details: {
      refundId: refund.id,
      paymentId,
      orderIdGuess,
    },
  });
}

/**
 * Callable: bump another user's likes_received (rules block client writes to other profiles).
 * Flutter creates/deletes likes/{callerDocId}_{targetUserId} first, then calls this.
 */
exports.updateLikesReceived = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be signed in to update like counts."
    );
  }

  const targetUserId = (data?.targetUserId || "").toString().trim();
  const increment = Number(data?.increment);
  if (!targetUserId || (increment !== 1 && increment !== -1)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "targetUserId and increment (+1 or -1) are required."
    );
  }

  const callerRef = await resolveUserRefByAuthUid(context.auth.uid);
  if (!callerRef) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Caller user profile not found."
    );
  }
  const callerDocId = callerRef.id;
  if (callerDocId === targetUserId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Cannot adjust likes_received for your own document via this API."
    );
  }

  const likeRef = db.collection("likes").doc(`${callerDocId}_${targetUserId}`);
  const likeSnap = await likeRef.get();

  if (increment === 1 && !likeSnap.exists) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Like record must exist before incrementing likes_received."
    );
  }
  if (increment === -1 && likeSnap.exists) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Like record must be removed before decrementing likes_received."
    );
  }

  const userRef = db.collection("users").doc(targetUserId);

  let targetMissing = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      targetMissing = true;
      return;
    }
    const cur = snap.get("likes_received");
    const n = typeof cur === "number" && !Number.isNaN(cur) ? cur : 0;
    const next = Math.max(0, n + increment);
    tx.update(userRef, {
      likes_received: next,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  if (targetMissing) {
    throw new functions.https.HttpsError("not-found", "Target user not found.");
  }

  return { success: true, targetUserId, increment };
});

exports.sendBirthRequest = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  await rateLimiter.consume(
    context.auth.uid,
    "sendBirthRequest",
    MATRIMONY_LIMITS.sendBirthRequest
  );

  const callerUid = context.auth.uid;
  const payload = readAccessRequestPayload(data);
  const parsedRequestId = parseRequestId(payload.requestId);
  const callerRef = await resolveCallerProfileRef(
    context,
    payload.requesterId || parsedRequestId?.requesterId || ""
  );
  if (!callerRef) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Caller profile mapping not found."
    );
  }
  const requesterId = callerRef.id;
  const ownerId =
    payload.ownerId || parsedRequestId?.ownerId || "";
  let requesterProfileId = (data?.requesterProfileId || data?.requester_profile_id || "")
    .toString()
    .trim();
  let requesterName = (data?.requesterName || data?.requester_name || "")
    .toString()
    .trim();
  const ownerProfileId = (data?.ownerProfileId || data?.owner_profile_id || "")
    .toString()
    .trim();
  const ownerName = (data?.ownerName || data?.owner_name || "").toString().trim();
  const forceResend = payload.forceResend;

  if (!requesterId || !ownerId || requesterId === ownerId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid requester/owner.");
  }

  const ownerDoc = await db.collection("users").doc(ownerId).get();
  const ownerData = ownerDoc.data() || {};
  const ownerAuthUid = (ownerData.auth_uid || "").toString().trim();
  const callerDoc = await callerRef.get();
  const callerData = callerDoc.data() || {};
  if (!requesterProfileId) {
    requesterProfileId = (callerData.profile_id || "").toString().trim();
  }
  if (!requesterName) {
    requesterName = (callerData.first_name || callerData.profile?.firstName || "Member")
      .toString()
      .trim();
  }
  const resolvedOwnerProfileId =
    ownerProfileId ||
    (ownerData.profile_id || "").toString().trim() ||
    ownerId;
  const resolvedOwnerName =
    ownerName ||
    (ownerData.first_name || ownerData.profile?.firstName || "Member")
      .toString()
      .trim();

  const docId = `${requesterId}_${ownerId}`;
  console.log("BIRTH_REQUEST_SEND", {
    callerUid,
    requesterId,
    ownerId,
    docId,
    forceResend,
  });
  const reqRef = db.collection("birth_requests").doc(docId);
  const existing = await reqRef.get();
  if (existing.exists) {
    const row = existing.data() || {};
    const status = normalizeAccessStatus(row.status);
    if (status === "pending" && !forceResend) {
      return { success: true, requestId: docId, status: "pending", duplicateIgnored: true };
    }
    if (status === "granted") {
      return { success: true, requestId: docId, status: "granted", duplicateIgnored: true };
    }
    if (!forceResend && status === "denied") {
      const deniedMs = parseDeniedOrRevokedAtMs(row);
      if (deniedMs && Date.now() - deniedMs < DENY_RESEND_COOLDOWN_MS) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Please wait before sending another birth details request."
        );
      }
    }
    if (!forceResend && status === "revoked") {
      const revokedMs = parseDeniedOrRevokedAtMs(row);
      if (revokedMs && Date.now() - revokedMs < REVOKE_RESEND_COOLDOWN_MS) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Please wait before re-requesting after access was revoked."
        );
      }
    }
    if (status !== "pending") {
      await reqRef.delete();
    }
  }

  const nowIso = new Date().toISOString();
  await reqRef.set({
    requester_id: requesterId,
    requester_auth_uid: callerUid,
    requester_profile_id: requesterProfileId || requesterId,
    requester_name: requesterName || "Member",
    owner_id: ownerId,
    owner_auth_uid: ownerAuthUid,
    owner_profile_id: resolvedOwnerProfileId,
    owner_name: resolvedOwnerName,
    status: "pending",
    requestCreatedAt: nowIso,
    request_created_at: nowIso,
    created_at: nowIso,
    updated_at: nowIso,
    lastTransition: "->pending",
    actorRole: "requester",
    actedBy: callerUid,
  });

  try {
    await db.collection("notifications").add({
      user_id: ownerId,
      to_user: ownerId,
      from_user: callerUid,
      type: "birth_request",
      title: "Birth Details Request",
      body: `${requesterName || "A user"} wants to view your birth details.`,
      message: `${requesterName || "A user"} wants to view your birth details.`,
      related_profile_id: requesterProfileId || requesterId,
      related_user_id: requesterId,
      request_doc_id: docId,
      is_read: false,
      created_at: nowIso,
    });
  } catch (e) {
    console.warn("sendBirthRequest notification failed:", e?.message || e);
  }

  return { success: true, requestId: docId, status: "pending" };
});

exports.sendCommunityRequest = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  await rateLimiter.consume(
    context.auth.uid,
    "sendCommunityRequest",
    MATRIMONY_LIMITS.sendCommunityRequest
  );

  const callerUid = context.auth.uid;
  const payload = readAccessRequestPayload(data);
  const parsedRequestId = parseRequestId(payload.requestId);
  const callerRef = await resolveCallerProfileRef(
    context,
    payload.requesterId || parsedRequestId?.requesterId || ""
  );
  if (!callerRef) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Caller profile mapping not found."
    );
  }
  const requesterId = callerRef.id;
  const ownerId =
    payload.ownerId || parsedRequestId?.ownerId || "";
  let requesterProfileId = (data?.requesterProfileId || data?.requester_profile_id || "")
    .toString()
    .trim();
  let requesterName = (data?.requesterName || data?.requester_name || "")
    .toString()
    .trim();
  const ownerProfileId = (data?.ownerProfileId || data?.owner_profile_id || "")
    .toString()
    .trim();
  const ownerName = (data?.ownerName || data?.owner_name || "").toString().trim();
  const forceResend = payload.forceResend;

  if (!requesterId || !ownerId || requesterId === ownerId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid requester/owner.");
  }

  const ownerDoc = await db.collection("users").doc(ownerId).get();
  const ownerData = ownerDoc.data() || {};
  const ownerAuthUid = (ownerData.auth_uid || "").toString().trim();
  const callerDoc = await callerRef.get();
  const callerData = callerDoc.data() || {};
  if (!requesterProfileId) {
    requesterProfileId = (callerData.profile_id || "").toString().trim();
  }
  if (!requesterName) {
    requesterName = (callerData.first_name || callerData.profile?.firstName || "Member")
      .toString()
      .trim();
  }
  const resolvedOwnerProfileId =
    ownerProfileId ||
    (ownerData.profile_id || "").toString().trim() ||
    ownerId;
  const resolvedOwnerName =
    ownerName ||
    (ownerData.first_name || ownerData.profile?.firstName || "Member")
      .toString()
      .trim();

  const requestId = `${requesterId}_${ownerId}`;
  console.log("COMMUNITY_REQUEST_SEND", {
    callerUid,
    requesterId,
    ownerId,
    requestId,
    forceResend,
  });
  const reqRef = db.collection("community_reference_requests").doc(requestId);
  const existing = await reqRef.get();
  if (existing.exists) {
    const row = existing.data() || {};
    const status = normalizeAccessStatus(row.status);
    if (status === "pending" && !forceResend) {
      return { success: true, requestId, status: "pending", duplicateIgnored: true };
    }
    if (status === "granted") {
      return { success: true, requestId, status: "granted", duplicateIgnored: true };
    }
    if (!forceResend && status === "denied") {
      const deniedMs = parseDeniedOrRevokedAtMs(row);
      if (deniedMs && Date.now() - deniedMs < DENY_RESEND_COOLDOWN_MS) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Please wait before sending another community reference request."
        );
      }
    }
    if (!forceResend && status === "revoked") {
      const revokedMs = parseDeniedOrRevokedAtMs(row);
      if (revokedMs && Date.now() - revokedMs < REVOKE_RESEND_COOLDOWN_MS) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Please wait before re-requesting after access was revoked."
        );
      }
    }
    if (status !== "pending") {
      await reqRef.delete();
    }
  }

  const nowIso = new Date().toISOString();
  await reqRef.set({
    requester_id: requesterId,
    requester_auth_uid: callerUid,
    requester_profile_id: requesterProfileId || requesterId,
    requester_name: requesterName || "Member",
    owner_id: ownerId,
    owner_auth_uid: ownerAuthUid,
    owner_profile_id: resolvedOwnerProfileId,
    owner_name: resolvedOwnerName,
    status: "pending",
    requestCreatedAt: nowIso,
    request_created_at: nowIso,
    created_at: nowIso,
    updated_at: nowIso,
    lastTransition: "->pending",
    actorRole: "requester",
    actedBy: callerUid,
  });

  try {
    await db.collection("notifications").add({
      user_id: ownerId,
      to_user: ownerId,
      from_user: callerUid,
      type: "community_reference_request",
      title: "Community Reference Request",
      body: `${requesterName || "A user"} requested to view your community references.`,
      is_read: false,
      created_at: nowIso,
      data: {
        requester_id: requesterId,
        requester_name: requesterName,
        requester_profile_id: requesterProfileId || requesterId,
        request_doc_id: requestId,
        related_user_id: requesterId,
      },
    });
  } catch (e) {
    console.warn("sendCommunityRequest notification failed:", e?.message || e);
  }

  return { success: true, requestId, status: "pending" };
});

exports.withdrawBirthRequest = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const payload = readAccessRequestPayload(data);
  const parsed = parseRequestId(payload.requestId);
  const callerRef = await resolveCallerProfileRef(
    context,
    payload.requesterId || parsed?.requesterId || ""
  );
  const requesterId = callerRef?.id || parsed?.requesterId || "";
  const ownerId = payload.ownerId || parsed?.ownerId || "";
  console.log("DEBUG withdrawBirthRequest input", {
    callerUid: context.auth.uid,
    payload,
    parsedRequesterId: parsed?.requesterId || "",
    parsedOwnerId: parsed?.ownerId || "",
    resolvedRequesterId: requesterId,
    ownerId,
  });
  if (!requesterId || !ownerId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing requesterId or ownerId");
  }
  const resolved = await resolveAccessRequestDocRef("birth_requests", {
    requestId: payload.requestId,
    requesterId,
    ownerId,
    authUid: context.auth.uid,
  });
  if (!resolved) {
    return {
      success: true,
      requestId: payload.requestId || `${requesterId}_${ownerId}`,
      deleted: false,
      reason: "not_found",
    };
  }
  const { ref, snap, requestId } = resolved;
  console.log("BIRTH_REQUEST_WITHDRAW", {
    callerUid: context.auth.uid,
    requesterId,
    ownerId,
    requestId,
  });
  const status = (snap.data()?.status || "").toString().toLowerCase();
  if (status !== "pending") {
    return {
      success: true,
      requestId,
      deleted: false,
      reason: "already_processed",
      status,
    };
  }
  await ref.set(
    {
      status: "withdrawn",
      withdrawn_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      lastTransition: `${status || "pending"}->withdrawn`,
      actorRole: "requester",
      actedBy: context.auth.uid,
    },
    { merge: true }
  );
  return { success: true, requestId, deleted: true, status: "withdrawn" };
});

exports.withdrawCommunityRequest = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const payload = readAccessRequestPayload(data);
  const parsed = parseRequestId(payload.requestId);
  const callerRef = await resolveCallerProfileRef(
    context,
    payload.requesterId || parsed?.requesterId || ""
  );
  const requesterId = callerRef?.id || parsed?.requesterId || "";
  const ownerId = payload.ownerId || parsed?.ownerId || "";
  console.log("DEBUG withdrawCommunityRequest input", {
    callerUid: context.auth.uid,
    payload,
    parsedRequesterId: parsed?.requesterId || "",
    parsedOwnerId: parsed?.ownerId || "",
    resolvedRequesterId: requesterId,
    ownerId,
  });
  if (!requesterId || !ownerId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing requesterId or ownerId");
  }
  const resolved = await resolveAccessRequestDocRef("community_reference_requests", {
    requestId: payload.requestId,
    requesterId,
    ownerId,
    authUid: context.auth.uid,
  });
  if (!resolved) {
    return {
      success: true,
      requestId: payload.requestId || `${requesterId}_${ownerId}`,
      deleted: false,
      reason: "not_found",
    };
  }
  const { ref, snap, requestId } = resolved;
  console.log("COMMUNITY_REQUEST_WITHDRAW", {
    callerUid: context.auth.uid,
    requesterId,
    ownerId,
    requestId,
  });
  const status = (snap.data()?.status || "").toString().toLowerCase();
  if (status !== "pending") {
    return {
      success: true,
      requestId,
      deleted: false,
      reason: "already_processed",
      status,
    };
  }
  await ref.set(
    {
      status: "withdrawn",
      withdrawn_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      lastTransition: `${status || "pending"}->withdrawn`,
      actorRole: "requester",
      actedBy: context.auth.uid,
    },
    { merge: true }
  );
  return { success: true, requestId, deleted: true, status: "withdrawn" };
});

exports.transitionBirthRequestStatus = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  await rateLimiter.consume(
    context.auth.uid,
    "transitionBirthRequestStatus",
    MATRIMONY_LIMITS.transitionBirthRequestStatus
  );
  const rawActionBirth = (data?.action || "").toString().trim().toLowerCase();
  if (rawActionBirth === "revoke" || rawActionBirth === "stop") {
    await rateLimiter.consume(
      context.auth.uid,
      "privacyRevokeAccess",
      MATRIMONY_LIMITS.privacyRevokeAccess
    );
  }

  const requestId = assertValidRequestDocId(data?.requestId || data?.request_id);
  const rawAction = rawActionBirth;
  const action =
    rawAction === "grant" ||
    rawAction === "granted" ||
    rawAction === "approve" ||
    rawAction === "approved" ||
    rawAction === "accept" ||
    rawAction === "accepted"
      ? "grant"
      : rawAction === "deny" ||
          rawAction === "denied" ||
          rawAction === "reject" ||
          rawAction === "rejected" ||
          rawAction === "decline" ||
          rawAction === "declined"
        ? "deny"
        : rawAction === "revoke" || rawAction === "revoked"
          ? "revoke"
          : rawAction === "stop" || rawAction === "stopped"
            ? "stop"
            : "";
  if (!["grant", "deny", "revoke", "stop"].includes(action)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "action must be grant, deny, revoke, or stop."
    );
  }

  const ref = db.collection("birth_requests").doc(requestId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Birth request not found.");
  }
  const row = snap.data() || {};
  const ownerId = (row.owner_id || "").toString().trim();
  const requesterId = (row.requester_id || "").toString().trim();
  assertPrivacyRequestBinding(requestId, requesterId, ownerId);

  const currentStatus = normalizeAccessStatus(row.status);
  const callerRef = await resolveUserRefByAuthUid(context.auth.uid);
  const callerDocId = callerRef ? callerRef.id : "";
  if (!isElevatedAdminContext(context) && callerDocId !== ownerId) {
    throw new functions.https.HttpsError("permission-denied", "Only owner can respond.");
  }

  const isGrant = action === "grant";
  const isDeny = action === "deny";
  const isRevoke = action === "revoke";
  const isStop = action === "stop";

  if (isDeny && currentStatus !== "pending") {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }
  if ((isRevoke || isStop) && currentStatus !== "granted") {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }
  if (isGrant && currentStatus === "granted") {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }
  if (isGrant && !["pending", "revoked", "stopped", "denied"].includes(currentStatus)) {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }

  const nextStatus = isGrant
    ? "granted"
    : isDeny
      ? "denied"
      : isStop
        ? "stopped"
        : "revoked";
  const nowIso = new Date().toISOString();
  const existingGrantedAt = row.grantedAt || row.granted_at;

  const patch = applyTransitionAudit(
    {
      updated_at: nowIso,
      updatedAt: nowIso,
    },
    {
      fromStatus: currentStatus,
      toStatus: nextStatus,
      actorUid: context.auth.uid,
      actorRole: "owner",
      row,
    }
  );

  if (isGrant && !existingGrantedAt) {
    patch.grantedAt = nowIso;
    patch.granted_at = nowIso;
  }
  if (isDeny) {
    patch.deniedAt = nowIso;
    patch.denied_at = nowIso;
  }
  if (isRevoke) {
    patch.revokedAt = nowIso;
    patch.revoked_at = nowIso;
    if (!existingGrantedAt) {
      patch.grantedAt = nowIso;
      patch.granted_at = nowIso;
    }
  }
  if (isStop) {
    patch.stoppedAt = nowIso;
    patch.stopped_at = nowIso;
    if (!existingGrantedAt) {
      patch.grantedAt = nowIso;
      patch.granted_at = nowIso;
    }
  }

  await ref.set(patch, { merge: true });

  const ownerName = (row.owner_name || "Profile Owner").toString();
  await notifyRequesterOutcome(db, {
    kind: "birth",
    outcome: nextStatus,
    requesterId,
    ownerId,
    ownerName,
    requestDocId: requestId,
    requesterProfileId: (row.requester_profile_id || "").toString(),
  });

  return { success: true, requestId, status: nextStatus };
});

exports.transitionCommunityRequestStatus = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  await rateLimiter.consume(
    context.auth.uid,
    "transitionCommunityRequestStatus",
    MATRIMONY_LIMITS.transitionCommunityRequestStatus
  );
  const rawActionCommunity = (data?.action || "").toString().trim().toLowerCase();
  if (rawActionCommunity === "revoke" || rawActionCommunity === "stop") {
    await rateLimiter.consume(
      context.auth.uid,
      "privacyRevokeAccess",
      MATRIMONY_LIMITS.privacyRevokeAccess
    );
  }

  const requestId = assertValidRequestDocId(data?.requestId || data?.request_id);
  const rawAction = rawActionCommunity;
  const action =
    rawAction === "grant" ||
    rawAction === "granted" ||
    rawAction === "approve" ||
    rawAction === "approved" ||
    rawAction === "accept" ||
    rawAction === "accepted"
      ? "grant"
      : rawAction === "deny" ||
          rawAction === "denied" ||
          rawAction === "reject" ||
          rawAction === "rejected" ||
          rawAction === "decline" ||
          rawAction === "declined"
        ? "deny"
        : rawAction === "revoke" || rawAction === "revoked"
          ? "revoke"
          : rawAction === "stop" || rawAction === "stopped"
            ? "stop"
            : "";
  if (!["grant", "deny", "revoke", "stop"].includes(action)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "action must be grant, deny, revoke, or stop."
    );
  }

  const ref = db.collection("community_reference_requests").doc(requestId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Community request not found.");
  }
  const row = snap.data() || {};
  const ownerId = (row.owner_id || "").toString().trim();
  const requesterId = (row.requester_id || "").toString().trim();
  assertPrivacyRequestBinding(requestId, requesterId, ownerId);

  const currentStatus = normalizeAccessStatus(row.status);
  const callerRef = await resolveUserRefByAuthUid(context.auth.uid);
  const callerDocId = callerRef ? callerRef.id : "";
  if (!isElevatedAdminContext(context) && callerDocId !== ownerId) {
    throw new functions.https.HttpsError("permission-denied", "Only owner can respond.");
  }

  const isGrant = action === "grant";
  const isDeny = action === "deny";
  const isRevoke = action === "revoke";
  const isStop = action === "stop";

  if (isDeny && currentStatus !== "pending") {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }
  if ((isRevoke || isStop) && currentStatus !== "granted") {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }
  if (isGrant && currentStatus === "granted") {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }
  if (isGrant && !["pending", "revoked", "stopped", "denied"].includes(currentStatus)) {
    return { success: true, requestId, status: currentStatus, duplicateIgnored: true };
  }

  const nextStatus = isGrant
    ? "granted"
    : isDeny
      ? "denied"
      : isStop
        ? "stopped"
        : "revoked";
  const nowIso = new Date().toISOString();
  const existingGrantedAt = row.grantedAt || row.granted_at;

  const patch = applyTransitionAudit(
    {
      updated_at: nowIso,
      updatedAt: nowIso,
    },
    {
      fromStatus: currentStatus,
      toStatus: nextStatus,
      actorUid: context.auth.uid,
      actorRole: "owner",
      row,
    }
  );

  if (isGrant && !existingGrantedAt) {
    patch.grantedAt = nowIso;
    patch.granted_at = nowIso;
  }
  if (isDeny) {
    patch.deniedAt = nowIso;
    patch.denied_at = nowIso;
  }
  if (isRevoke) {
    patch.revokedAt = nowIso;
    patch.revoked_at = nowIso;
    if (!existingGrantedAt) {
      patch.grantedAt = nowIso;
      patch.granted_at = nowIso;
    }
  }
  if (isStop) {
    patch.stoppedAt = nowIso;
    patch.stopped_at = nowIso;
    if (!existingGrantedAt) {
      patch.grantedAt = nowIso;
      patch.granted_at = nowIso;
    }
  }

  await ref.set(patch, { merge: true });

  if (nextStatus === "granted") {
    await db.collection("community_reference_access").doc(requestId).set({
      requester_id: requesterId,
      requester_auth_uid: (row.requester_auth_uid || "").toString().trim(),
      owner_id: ownerId,
      owner_auth_uid: (row.owner_auth_uid || "").toString().trim(),
      granted_at: nowIso,
    }, { merge: true });
  } else {
    await db.collection("community_reference_access").doc(requestId).delete().catch(() => null);
  }

  const ownerName = (row.owner_name || "Profile Owner").toString();
  await notifyRequesterOutcome(db, {
    kind: "community",
    outcome: nextStatus,
    requesterId,
    ownerId,
    ownerName,
    requestDocId: requestId,
    requesterProfileId: (row.requester_profile_id || "").toString(),
  });

  return { success: true, requestId, status: nextStatus };
});

/**
 * One-time admin migration:
 * Convert interests.from_user_id/to_user_id values from auth UID -> users/{profileDocId}.
 *
 * Input:
 *  - dryRun?: boolean (default true)
 *  - limit?: number (default 200, max 250)
 */
exports.migrateInterestIdsToProfileDocIds = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const callerIsAdmin = await isCallerElevatedAdmin(context);
  if (!callerIsAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }

  const dryRun = data?.dryRun !== false;
  const rawLimit = Number(data?.limit);
  const limit = Number.isFinite(rawLimit)
    ? Math.max(1, Math.min(250, Math.trunc(rawLimit)))
    : 200;

  const snap = await db.collection("interests").limit(limit).get();
  if (snap.empty) {
    return {
      success: true,
      dryRun,
      scanned: 0,
      migrated: 0,
      skipped: 0,
      unresolved: 0,
      details: [],
    };
  }

  const userDocExistsCache = new Map();
  const authUidToDocIdCache = new Map();
  async function resolveProfileDocId(rawId) {
    const id = (rawId || "").toString().trim();
    if (!id) return "";

    if (userDocExistsCache.has(id)) {
      const exists = userDocExistsCache.get(id);
      if (exists) return id;
    } else {
      const byDoc = await db.collection("users").doc(id).get();
      userDocExistsCache.set(id, byDoc.exists);
      if (byDoc.exists) return id;
    }

    if (authUidToDocIdCache.has(id)) return authUidToDocIdCache.get(id);
    const byAuth = await db
      .collection("users")
      .where("auth_uid", "==", id)
      .limit(1)
      .get();
    const resolved = byAuth.empty ? "" : byAuth.docs[0].id;
    authUidToDocIdCache.set(id, resolved);
    return resolved;
  }

  const details = [];
  let migrated = 0;
  let skipped = 0;
  let unresolved = 0;
  const batch = db.batch();

  for (const doc of snap.docs) {
    const row = doc.data() || {};
    const fromRaw = (row.from_user_id || "").toString().trim();
    const toRaw = (row.to_user_id || "").toString().trim();

    if (!fromRaw || !toRaw) {
      skipped += 1;
      details.push({ interestId: doc.id, status: "skipped_invalid", fromRaw, toRaw });
      continue;
    }

    const fromResolved = await resolveProfileDocId(fromRaw);
    const toResolved = await resolveProfileDocId(toRaw);
    if (!fromResolved || !toResolved) {
      unresolved += 1;
      details.push({
        interestId: doc.id,
        status: "unresolved",
        fromRaw,
        toRaw,
        fromResolved,
        toResolved,
      });
      continue;
    }

    if (fromResolved === fromRaw && toResolved === toRaw) {
      skipped += 1;
      details.push({ interestId: doc.id, status: "already_migrated" });
      continue;
    }

    const newDocId = `${fromResolved}_${toResolved}`;
    if (!dryRun) {
      const targetRef = db.collection("interests").doc(newDocId);
      batch.set(
        targetRef,
        {
          ...row,
          from_user_id: fromResolved,
          to_user_id: toResolved,
          migrated_from_doc_id: doc.id,
          migrated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      batch.delete(doc.ref);
    }
    migrated += 1;
    details.push({
      interestId: doc.id,
      status: dryRun ? "would_migrate" : "migrated",
      toInterestId: newDocId,
      fromRaw,
      toRaw,
      fromResolved,
      toResolved,
    });
  }

  if (!dryRun && migrated > 0) {
    await batch.commit();
  }

  return {
    success: true,
    dryRun,
    scanned: snap.size,
    migrated,
    skipped,
    unresolved,
    details,
  };
});

/**
 * One-time admin migration:
 * Convert requester_id/owner_id values from auth UID -> users/{profileDocId}
 * for birth_requests and community_reference_requests.
 *
 * Input:
 *  - dryRun?: boolean (default true)
 *  - limit?: number (default 200, max 250)
 */
async function migrateRequestIdsToProfileDocIds({
  collectionName,
  dryRun,
  limit,
}) {
  const snap = await db.collection(collectionName).limit(limit).get();
  if (snap.empty) {
    return {
      collection: collectionName,
      scanned: 0,
      migrated: 0,
      skipped: 0,
      unresolved: 0,
      details: [],
    };
  }

  const userDocExistsCache = new Map();
  const authUidToDocIdCache = new Map();
  async function resolveProfileDocId(rawId) {
    const id = (rawId || "").toString().trim();
    if (!id) return "";

    if (userDocExistsCache.has(id)) {
      const exists = userDocExistsCache.get(id);
      if (exists) return id;
    } else {
      const byDoc = await db.collection("users").doc(id).get();
      userDocExistsCache.set(id, byDoc.exists);
      if (byDoc.exists) return id;
    }

    if (authUidToDocIdCache.has(id)) return authUidToDocIdCache.get(id);
    const byAuth = await db.collection("users").where("auth_uid", "==", id).limit(1).get();
    const resolved = byAuth.empty ? "" : byAuth.docs[0].id;
    authUidToDocIdCache.set(id, resolved);
    return resolved;
  }

  const details = [];
  let migrated = 0;
  let skipped = 0;
  let unresolved = 0;
  const batch = db.batch();

  for (const doc of snap.docs) {
    const row = doc.data() || {};
    const requesterRaw = (row.requester_id || "").toString().trim();
    const ownerRaw = (row.owner_id || "").toString().trim();

    if (!requesterRaw || !ownerRaw) {
      skipped += 1;
      details.push({
        requestId: doc.id,
        status: "skipped_invalid",
        requesterRaw,
        ownerRaw,
      });
      continue;
    }

    const requesterResolved = await resolveProfileDocId(requesterRaw);
    const ownerResolved = await resolveProfileDocId(ownerRaw);
    if (!requesterResolved || !ownerResolved) {
      unresolved += 1;
      details.push({
        requestId: doc.id,
        status: "unresolved",
        requesterRaw,
        ownerRaw,
        requesterResolved,
        ownerResolved,
      });
      continue;
    }

    if (requesterResolved === requesterRaw && ownerResolved === ownerRaw) {
      skipped += 1;
      details.push({ requestId: doc.id, status: "already_migrated" });
      continue;
    }

    const newDocId = `${requesterResolved}_${ownerResolved}`;
    if (!dryRun) {
      const targetRef = db.collection(collectionName).doc(newDocId);
      batch.set(
        targetRef,
        {
          ...row,
          requester_id: requesterResolved,
          owner_id: ownerResolved,
          migrated_from_doc_id: doc.id,
          migrated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      batch.delete(doc.ref);
    }
    migrated += 1;
    details.push({
      requestId: doc.id,
      status: dryRun ? "would_migrate" : "migrated",
      toRequestId: newDocId,
      requesterRaw,
      ownerRaw,
      requesterResolved,
      ownerResolved,
    });
  }

  if (!dryRun && migrated > 0) {
    await batch.commit();
  }

  return {
    collection: collectionName,
    scanned: snap.size,
    migrated,
    skipped,
    unresolved,
    details,
  };
}

exports.migrateBirthAndCommunityRequestIdsToProfileDocIds = fnAsia.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    const callerIsAdmin = await isCallerElevatedAdmin(context);
    if (!callerIsAdmin) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required.");
    }

    const dryRun = data?.dryRun !== false;
    const rawLimit = Number(data?.limit);
    const limit = Number.isFinite(rawLimit)
      ? Math.max(1, Math.min(250, Math.trunc(rawLimit)))
      : 200;

    const [birth, community] = await Promise.all([
      migrateRequestIdsToProfileDocIds({
        collectionName: "birth_requests",
        dryRun,
        limit,
      }),
      migrateRequestIdsToProfileDocIds({
        collectionName: "community_reference_requests",
        dryRun,
        limit,
      }),
    ]);

    return {
      success: true,
      dryRun,
      limit,
      collections: {
        birth_requests: birth,
        community_reference_requests: community,
      },
      totals: {
        scanned: (birth.scanned || 0) + (community.scanned || 0),
        migrated: (birth.migrated || 0) + (community.migrated || 0),
        skipped: (birth.skipped || 0) + (community.skipped || 0),
        unresolved: (birth.unresolved || 0) + (community.unresolved || 0),
      },
    };
  }
);

/**
 * Secure MPIN write path.
 * Uses Admin SDK to avoid client rule brittleness when auth_uid/doc-id mapping drifts.
 *
 * Input:
 *  - userId: string (Firestore users doc id)
 *  - mpin_hash: string (already hashed on client)
 */
exports.setUserMpinSecure = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const userId = (data?.userId || "").toString().trim();
  const mpinHash = (data?.mpin_hash || "").toString().trim();
  const mobileNumber = (data?.mobileNumber || "").toString().trim();

  // Diagnostic logging
  console.log(`[setUserMpinSecure] Called by ${context.auth.uid}`);
  console.log(`[setUserMpinSecure] userId=${userId}, mpinHash=${mpinHash.substring(0, 16)}...`);

  if (!userId || !mpinHash) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "userId and mpin_hash are required."
    );
  }
  if (mpinHash.length < 32) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid mpin_hash.");
  }

  const callerUid = context.auth.uid;
  const callerIsAdmin = await isCallerElevatedAdmin(context);
  const ref = db.collection("users").doc(userId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }
  const row = snap.data() || {};
  const existingAuthUid = (row.auth_uid || "").toString().trim();
  const docMobile = (row.mobile_number || row.mobileNumber || "").toString().trim();
  const normalizedReqMobile = mobileNumber.replace(/\D/g, "").replace(/^91/, "");
  const normalizedDocMobile = docMobile.replace(/\D/g, "").replace(/^91/, "");
  const mobileMatched = normalizedReqMobile.length >= 10 &&
    normalizedDocMobile.length >= 10 &&
    normalizedReqMobile === normalizedDocMobile;
  const ownerAllowed =
    callerIsAdmin ||
    userId === callerUid ||
    existingAuthUid === callerUid ||
    existingAuthUid === "" ||
    mobileMatched;
  if (!ownerAllowed) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "You are not allowed to set MPIN for this user."
    );
  }

  await ref.set(
    {
      mpin_hash: mpinHash,
      auth_uid: callerUid,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { success: true, userId };
});

/**
 * Admin retry for premium entitlement after fixing auth_uid linkage.
 *
 * Input:
 *  - orderId: string (required)
 *  - paymentId: string (optional; derived from payments/{orderId}.paymentId if missing)
 *  - dryRun?: boolean (default false)
 */
exports.retryPremiumEntitlement = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const callerIsAdmin = await isCallerElevatedAdmin(context);
  if (!callerIsAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }

  const orderId = (data?.orderId || "").toString().trim();
  let paymentId = (data?.paymentId || "").toString().trim();
  const dryRun = data?.dryRun === true;
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "orderId is required.");
  }

  const paymentRef = db.collection("payments").doc(orderId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Payment document not found.");
  }
  const paymentData = paymentSnap.data() || {};
  const uid = (paymentData.uid || "").toString().trim();
  const status = (paymentData.status || "").toString().toLowerCase();
  const amountPaise = Number(paymentData.amount || paymentData.amountPaid || 0);

  if (!paymentId) {
    paymentId = (paymentData.paymentId || "").toString().trim();
  }
  if (!paymentId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "paymentId missing in both request and payments document."
    );
  }
  if (!uid) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "uid missing in payment document."
    );
  }
  if (status && status !== "captured" && status !== "paid") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Payment status is '${status}', expected captured/paid.`
    );
  }

  // Parse planDays from common locations used by app + gateway payload mirrors.
  const planDaysRaw = paymentData.notes?.planDays ?? paymentData.planDays;
  const planDays = Number(planDaysRaw || 30);

  if (dryRun) {
    const userRef = await resolveUserRefByAuthUid(uid);
    return {
      success: true,
      dryRun: true,
      orderId,
      paymentId,
      uid,
      status,
      planDays: Number.isFinite(planDays) && planDays > 0 ? planDays : 30,
      canResolveUserProfile: !!userRef,
      resolvedUserDocId: userRef ? userRef.id : "",
    };
  }

  const applyResult = await applyPremiumEntitlementIfNeeded({
    orderId,
    paymentId,
    uid,
    amountPaise: Number.isFinite(amountPaise) ? amountPaise : 0,
    planDays,
    source: "admin_retry_callable",
  });

  await db.collection("payment_retry_logs").add({
    orderId,
    paymentId,
    uid,
    actorUid: context.auth.uid,
    dryRun: false,
    result: applyResult,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    orderId,
    paymentId,
    uid,
    applyResult,
  };
});

async function logInterestTransition({
  interestId,
  action,
  actorUid,
  result,
  fromStatus = "",
  toStatus = "",
}) {
  try {
    await db.collection("interest_logs").add({
      interestId,
      action,
      actor: actorUid,
      result,
      fromStatus,
      toStatus,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.warn("interest transition log write failed:", e?.message || e);
  }
}

const { createMatrimonyShared } = require("./src/matrimony_shared");
const {
  createCreatePhotoRequestCallable,
} = require("./src/createPhotoRequest");

const matrimonyShared = createMatrimonyShared(db);

async function writeSecurityAudit(event, fields) {
  try {
    await db.collection("security_audit_logs").add({
      event,
      module: "matrimony_gateway",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      ...fields,
    });
  } catch (e) {
    console.warn("security_audit_logs write failed:", e?.message || e);
  }
}

const matrimonyDeps = {
  resolveUserRefByAuthUid,
  resolveCallerProfileRef,
  resolveUserDocRefByAnyId: resolveUserDocRefForAdmin,
  logInterestTransition,
  rateLimiter,
  isBlockedPair: matrimonyShared.isBlockedPair,
  writeSecurityAudit,
};

const matrimonyCallables = require("./src/matrimony_gateway").registerMatrimonyCallables({
  db,
  admin,
  fnAsia,
  deps: matrimonyDeps,
});
exports.transitionInterestStatus = matrimonyCallables.transitionInterestStatus;
exports.createOrResendInterest = matrimonyCallables.createOrResendInterest;
exports.transitionPhotoRequest = matrimonyCallables.transitionPhotoRequest;
exports.createChatRoom = matrimonyCallables.createChatRoom;
exports.unlockContact = matrimonyCallables.unlockContact;
exports.validatePremiumAccess = matrimonyCallables.validatePremiumAccess;
exports.ensureSupportThread = matrimonyCallables.ensureSupportThread;
exports.sendSupportMessage = matrimonyCallables.sendSupportMessage;
exports.markSupportThreadRead = matrimonyCallables.markSupportThreadRead;

exports.createPhotoRequest = createCreatePhotoRequestCallable({
  db,
  admin,
  fnAsia,
  deps: {
    ...matrimonyDeps,
    resolveUserDocRefByAnyId: resolveUserDocRefForAdmin,
  },
});

const engagementCallables = require("./src/engagement_gateway").registerEngagementCallables({
  db,
  admin,
  fnAsia,
  deps: matrimonyDeps,
});
exports.recordProfileView = engagementCallables.recordProfileView;
exports.recordLike = engagementCallables.recordLike;

function isElevatedAdminContext(context) {
  const token = context.auth?.token || {};
  return token.admin === true || token.is_admin === true;
}

async function isCallerElevatedAdmin(context) {
  if (!context.auth?.uid) return false;
  if (isElevatedAdminContext(context)) return true;

  const uid = context.auth.uid;
  try {
    const [userDoc, sessionDoc] = await Promise.all([
      db.collection("users").doc(uid).get(),
      db.collection("admin_sessions").doc(uid).get(),
    ]);
    const userAdmin = userDoc.exists && userDoc.data()?.is_admin === true;
    const sessionAdmin = sessionDoc.exists && sessionDoc.data()?.is_admin === true;
    return userAdmin || sessionAdmin;
  } catch (e) {
    console.warn("admin verification fallback failed:", e?.message || e);
    return false;
  }
}

/**
 * Securely set/unset Firebase Auth custom admin claims.
 * Migration helper: keeps existing Firestore-admin fallback while moving to claims.
 */
exports.setAdminCustomClaim = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required."
    );
  }

  const callerIsAdmin = await isCallerElevatedAdmin(context);
  if (!callerIsAdmin) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only admins can manage admin claims."
    );
  }

  const targetUid = (data?.targetUid || "").toString().trim();
  const isAdmin = data?.isAdmin === true;
  if (!targetUid) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "targetUid is required."
    );
  }

  const targetUser = await admin.auth().getUser(targetUid);
  const existingClaims = targetUser.customClaims || {};
  const nextClaims = {
    ...existingClaims,
    admin: isAdmin,
    is_admin: isAdmin,
  };

  await admin.auth().setCustomUserClaims(targetUid, nextClaims);

  await db.collection("admin_claim_logs").add({
    actor_uid: context.auth.uid,
    target_uid: targetUid,
    is_admin: isAdmin,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    source: "setAdminCustomClaim_callable",
  });

  return {
    success: true,
    targetUid,
    isAdmin,
  };
});

// ═══════════════════════════════════════════════════════════════════════════
// FCM push — mirrors `notifications` creates (low Firestore billing)
// ═══════════════════════════════════════════════════════════════════════════
//
// Design (cost-aware):
// • One trigger invocation per in-app notification write (already in your flow).
// • Resolves device token with at most: 1× users.doc(recipientKey) + optional
//   1× query users.where("auth_uid","==",recipientKey).limit(1) when notifications
//   address the recipient by Firebase Auth UID instead of Firestore doc id.
// • Sends FCM only for an allowlist of types (skip noisy / marketing types).
// • On invalid token: one small merge to clear fcm_token on that user doc.
//
// Deploy: `firebase deploy --only functions:onInAppNotificationCreatedPushFCM`
// iOS: enable Push Notifications capability + APNs key in Firebase Console.

const FCM_PUSH_TYPES = new Set([
  "interest_received",
  "interest_reminder",
  "interest_accepted",
  "interest_declined",
  "interest_rejected",
  "birth_request",
  "community_reference_request",
  "photo_request",
]);

/**
 * @param {FirebaseFirestore.DocumentSnapshot} snap
 * @param {string} recipientKey
 * @returns {Promise<{token: (string|null), userRef: FirebaseFirestore.DocumentReference|null}>}
 */
async function resolveFcmTokenForRecipient(db, recipientKey) {
  const direct = await db.collection("users").doc(recipientKey).get();
  if (direct.exists) {
    const t = (direct.data() || {}).fcm_token;
    if (typeof t === "string" && t.length > 8) {
      return { token: t, userRef: direct.ref };
    }
  }
  const q = await db
    .collection("users")
    .where("auth_uid", "==", recipientKey)
    .limit(1)
    .get();
  if (!q.empty) {
    const doc = q.docs[0];
    const t = (doc.data() || {}).fcm_token;
    if (typeof t === "string" && t.length > 8) {
      return { token: t, userRef: doc.ref };
    }
  }
  return { token: null, userRef: null };
}

exports.onInAppNotificationCreatedPushFCM = fnAsia.firestore
  .document("notifications/{notifId}")
  .onCreate(async (snap, context) => {
    const d = snap.data();
    if (!d) return null;

    const type = (d.type || "").toString();
    if (!FCM_PUSH_TYPES.has(type)) {
      return null;
    }

    const recipientKey = (d.user_id || d.to_user || "").toString().trim();
    if (!recipientKey) {
      return null;
    }

    const { token, userRef } = await resolveFcmTokenForRecipient(db, recipientKey);
    if (!token) {
      console.log(
        `[FCM] skip — no token for recipientKey=${recipientKey} notif=${context.params.notifId}`,
      );
      return null;
    }

    const title = (d.title || "Mana Vivaaha Vedika").toString().slice(0, 120);
    const body = (d.body || d.message || "You have a new notification")
      .toString()
      .slice(0, 240);

    const message = {
      token,
      notification: { title, body },
      data: {
        type,
        notification_id: context.params.notifId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: { priority: "high" },
      apns: {
        payload: {
          aps: {
            sound: "default",
            contentAvailable: true,
          },
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log(`[FCM] sent type=${type} to=${recipientKey} id=${context.params.notifId}`);
    } catch (e) {
      const code = (e && (e.code || (e.errorInfo && e.errorInfo.code))) || "";
      console.error("[FCM] send failed", code, e && e.message);
      if (
        userRef &&
        (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token")
      ) {
        try {
          await userRef.set(
            {
              fcm_token: admin.firestore.FieldValue.delete(),
              fcm_token_invalidated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        } catch (inner) {
          console.error("[FCM] token cleanup failed", inner);
        }
      }
    }
    return null;
  });

function toIsoOrNull(value) {
  if (!value) return null;
  const dt = new Date(value);
  return Number.isNaN(dt.getTime()) ? null : dt.toISOString();
}

/**
 * Canonical user id for admin approval of payment_requests.
 * Prefer userDocId (Razorpay / app profile doc) over user_id when both exist,
 * so premium is never granted to the wrong row when ids disagree.
 */
function resolveTargetUserIdForPaymentRequest(reqData, clientFallbackUserId) {
  const data = reqData && typeof reqData === "object" ? reqData : {};
  const notes =
    data.notes && typeof data.notes === "object" && !Array.isArray(data.notes)
      ? data.notes
      : {};
  const candidates = [
    (data.userDocId || data.user_doc_id || "").toString().trim(),
    (notes.userDocId || notes.user_doc_id || "").toString().trim(),
    (data.user_id || "").toString().trim(),
    (data.uid || data.authUid || data.auth_uid || "").toString().trim(),
    (clientFallbackUserId || "").toString().trim(),
  ];
  for (const c of candidates) {
    if (c) return c;
  }
  return "";
}

function resolvePlanDaysForPaymentRequest(reqData, clientPlanDays) {
  const client = Number(clientPlanDays);
  if (Number.isFinite(client) && client > 0) {
    return Math.min(Math.floor(client), 3650);
  }
  const data = reqData && typeof reqData === "object" ? reqData : {};
  const notes =
    data.notes && typeof data.notes === "object" && !Array.isArray(data.notes)
      ? data.notes
      : {};
  const fromDoc = Number(data.plan_days ?? data.planDays ?? notes.planDays);
  if (Number.isFinite(fromDoc) && fromDoc > 0) {
    return Math.min(Math.floor(fromDoc), 3650);
  }
  return 30;
}

async function resolveUserDocRefForAdmin(userIdLike) {
  const raw = (userIdLike || "").toString().trim();
  if (!raw) return null;

  const byDoc = db.collection("users").doc(raw);
  const byDocSnap = await byDoc.get();
  if (byDocSnap.exists) return byDoc;

  const byProfile = await db
    .collection("users")
    .where("profile_id", "==", raw)
    .limit(1)
    .get();
  if (!byProfile.empty) return byProfile.docs[0].ref;

  const byAuthUid = await db
    .collection("users")
    .where("auth_uid", "==", raw)
    .limit(1)
    .get();
  if (!byAuthUid.empty) return byAuthUid.docs[0].ref;

  return null;
}

async function ensureCallerIsAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const ok = await isCallerElevatedAdmin(context);
  if (!ok) {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }
}

function buildMembershipPayload({ tier, startIso, expiryIso }) {
  const safeTier = (tier || "free").toString().trim().toLowerCase();
  const isPremium = safeTier === "platinum";
  const nowIso = new Date().toISOString();
  const startDateIso = startIso || nowIso;
  const expiryDateIso = isPremium ? expiryIso : null;

  return {
    membership_tier: safeTier,
    // Match client toDatabaseJson: status mirrors tier name for premium (not "verified").
    membership_status: isPremium ? safeTier : "free",
    membership_start_at: startDateIso,
    membership_expires_at: expiryDateIso,
    membership_expiry_date: expiryDateIso,
    premiumSince: isPremium ? startDateIso : admin.firestore.FieldValue.delete(),
    membership_json: {
      tier: safeTier,
      startDate: startDateIso,
      expiryDate: expiryDateIso,
      transactionId: null,
      paymentMethod: "admin_grant",
      amountPaid: null,
      contactsUsed: 0,
    },
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

exports.adminUpdateUserMembership = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);

  const userId = (data?.user_id || "").toString().trim();
  const tier = (data?.tier || "free").toString().trim().toLowerCase();
  const startIso = toIsoOrNull(data?.start_date);
  const expiryIso = toIsoOrNull(data?.expiry_date);
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "user_id is required.");
  }
  if (!["free", "platinum"].includes(tier)) {
    throw new functions.https.HttpsError("invalid-argument", "tier must be free or platinum.");
  }
  if (tier === "platinum" && !expiryIso) {
    throw new functions.https.HttpsError("invalid-argument", "expiry_date is required for platinum.");
  }

  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }

  const payload = buildMembershipPayload({ tier, startIso, expiryIso });
  await userRef.set(payload, { merge: true });

  return { success: true, user_id: userRef.id, tier };
});

exports.adminApproveUserMembership = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const userId = (data?.user_id || "").toString().trim();
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "user_id is required.");
  }
  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }

  const now = new Date();
  const expiry = new Date(now.getTime() + (30 * 24 * 60 * 60 * 1000));
  await userRef.set(
    buildMembershipPayload({
      tier: "platinum",
      startIso: now.toISOString(),
      expiryIso: expiry.toISOString(),
    }),
    { merge: true }
  );

  return { success: true, user_id: userRef.id, tier: "platinum" };
});

exports.adminSuspendUser = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const userId = (data?.user_id || "").toString().trim();
  const reason = (data?.reason || "Suspended by admin").toString().trim();
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "user_id is required.");
  }
  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }
  await userRef.set({
    membership_status: "suspended",
    suspension_reason: reason,
    suspended_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true, user_id: userRef.id };
});

exports.adminRejectUser = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const userId = (data?.user_id || "").toString().trim();
  const reason = (data?.reason || "Rejected by admin").toString().trim();
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "user_id is required.");
  }
  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }
  await userRef.set({
    membership_status: "rejected",
    rejection_reason: reason,
    rejected_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true, user_id: userRef.id };
});

exports.adminReactivateUser = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const userId = (data?.user_id || "").toString().trim();
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "user_id is required.");
  }
  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }
  await userRef.set({
    membership_status: "verified",
    suspension_reason: admin.firestore.FieldValue.delete(),
    rejected_at: admin.firestore.FieldValue.delete(),
    rejection_reason: admin.firestore.FieldValue.delete(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true, user_id: userRef.id };
});

exports.adminVerifyDocument = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const verificationId = (data?.verification_id || "").toString().trim();
  const isApproved = data?.is_approved === true;
  const rejectionReason = (data?.rejection_reason || "").toString().trim();
  if (!verificationId) {
    throw new functions.https.HttpsError("invalid-argument", "verification_id is required.");
  }
  const verificationRef = db.collection("profile_verifications").doc(verificationId);
  const verificationSnap = await verificationRef.get();
  if (!verificationSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Verification request not found.");
  }
  const status = isApproved ? "approved" : "rejected";
  await verificationRef.set({
    status,
    verified_at: admin.firestore.FieldValue.serverTimestamp(),
    verified_by: context.auth.uid,
    rejection_reason: isApproved ? admin.firestore.FieldValue.delete() : rejectionReason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true, verification_id: verificationId, status };
});

function displayNameFromUserData(data = {}) {
  const profile =
    data.profile && typeof data.profile === "object" ? data.profile : {};
  const first = (data.first_name || profile.first_name || "").toString().trim();
  const last = (data.last_name || profile.last_name || "").toString().trim();
  const full = `${first} ${last}`.trim();
  if (full) return full;
  return (data.profile_id || "Member").toString().trim();
}

function genderFromUserData(data = {}) {
  const profile =
    data.profile && typeof data.profile === "object" ? data.profile : {};
  return (data.gender || profile.gender || "").toString().toLowerCase().trim();
}

const {
  purgeUserRelatedData,
  pruneStaleProfileViewsForOwnerIds,
  pruneStaleAccessRequestsForOwnerIds,
  pruneStaleAccessRequestsForRequesterIds,
} = require("./src/profile_deletion_cleanup");

/**
 * Removes profile_views on the caller's profile where the viewer account was deleted.
 */
exports.pruneStaleProfileViewsForMe = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required."
    );
  }
  const callerRef = await resolveCallerProfileRef(
    context,
    (data?.requesterId || "").toString().trim()
  );
  if (!callerRef) {
    throw new functions.https.HttpsError("not-found", "Your profile could not be found.");
  }
  const callerSnap = await callerRef.get();
  const callerData = callerSnap.data() || {};
  const removed = await pruneStaleProfileViewsForOwnerIds(db, [
    callerRef.id,
    callerData.profile_id,
    callerData.auth_uid,
  ]);
  return { success: true, removed };
});

/**
 * Removes stale profile_views and pending access requests involving deleted accounts.
 */
exports.pruneStaleEngagementForMe = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required."
    );
  }
  const callerRef = await resolveCallerProfileRef(
    context,
    (data?.requesterId || "").toString().trim()
  );
  if (!callerRef) {
    throw new functions.https.HttpsError("not-found", "Your profile could not be found.");
  }
  const callerSnap = await callerRef.get();
  const callerData = callerSnap.data() || {};
  const identityIds = [
    callerRef.id,
    callerData.profile_id,
    callerData.auth_uid,
  ];
  const removedViews = await pruneStaleProfileViewsForOwnerIds(db, identityIds);
  const removedIncomingAccess = await pruneStaleAccessRequestsForOwnerIds(
    db,
    identityIds
  );
  const removedOutgoingAccess = await pruneStaleAccessRequestsForRequesterIds(
    db,
    identityIds
  );
  return {
    success: true,
    removedViews,
    removedIncomingAccess,
    removedOutgoingAccess,
  };
});

/**
 * Marriage fixed: immediate profile removal + success story when matched on-app.
 */
exports.completeMarriageFixed = fnAsia.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required."
    );
  }

  const callerRef = await resolveCallerProfileRef(
    context,
    (data?.requesterId || "").toString().trim()
  );
  if (!callerRef) {
    throw new functions.https.HttpsError(
      "not-found",
      "Your profile could not be found."
    );
  }

  const callerSnap = await callerRef.get();
  if (!callerSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Your profile could not be found.");
  }
  const callerData = callerSnap.data() || {};
  const callerProfileId = (callerData.profile_id || "").toString().trim();

  const skipStoryCreation = data?.skipStoryCreation === true;

  let matchSource = (data?.matchSource || "").toString().trim();
  let partnerProfileId = (data?.partnerProfileId || "").toString().trim();
  if (matchSource.includes(":")) {
    const colon = matchSource.indexOf(":");
    partnerProfileId = partnerProfileId || matchSource.slice(colon + 1).trim();
    matchSource = matchSource.slice(0, colon).trim();
  }

  const sourceLower = matchSource.toLowerCase();
  const isAppMatch =
    sourceLower.includes("mana") &&
    sourceLower.includes("vedika") &&
    partnerProfileId.length > 0;

  const now = admin.firestore.FieldValue.serverTimestamp();
  const marriedAtIso = new Date().toISOString();
  const batch = db.batch();
  let storyId = null;
  let partnerDocId = null;

  if (isAppMatch) {
    const partnerRef = await resolveUserDocRefForAdmin(partnerProfileId);
    if (!partnerRef) {
      throw new functions.https.HttpsError(
        "not-found",
        "Partner Profile ID was not found. Please check and try again."
      );
    }
    if (partnerRef.id === callerRef.id) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Partner cannot be your own profile."
      );
    }

    const partnerSnap = await partnerRef.get();
    const partnerData = partnerSnap.data() || {};
    partnerDocId = partnerRef.id;
    const partnerPublicId = (partnerData.profile_id || partnerProfileId)
      .toString()
      .trim();

    const callerGender = genderFromUserData(callerData);
    const partnerGender = genderFromUserData(partnerData);
    let groomProfileId = callerProfileId || callerRef.id;
    let brideProfileId = partnerPublicId || partnerRef.id;
    if (callerGender === "female" && partnerGender !== "female") {
      groomProfileId = partnerPublicId || partnerRef.id;
      brideProfileId = callerProfileId || callerRef.id;
    } else if (partnerGender === "female" && callerGender !== "female") {
      groomProfileId = callerProfileId || callerRef.id;
      brideProfileId = partnerPublicId || partnerRef.id;
    }

    if (!skipStoryCreation) {
      const callerName = displayNameFromUserData(callerData);
      const partnerName = displayNameFromUserData(partnerData);
      const storyRef = db.collection("success_stories").doc();
      storyId = storyRef.id;
      const storyPayload = {
        user_id: callerRef.id,
        created_by_user_id: callerRef.id,
        partner_user_id: partnerRef.id,
        groom_profile_id: groomProfileId,
        bride_profile_id: brideProfileId,
        couple_names: `${callerName} & ${partnerName}`,
        title: "Matched on mana Vivaaha Vedika",
        description:
          `${callerName} and ${partnerName} tied the knot after connecting on mana Vivaaha Vedika.`,
        match_source: "mana_Vivaaha Vedika",
        married_at: marriedAtIso,
        created_at: now,
        is_published: true,
      };
      const imageUrl = (data?.imageUrl || "").toString().trim();
      if (imageUrl) storyPayload.image_url = imageUrl;
      batch.set(storyRef, storyPayload);
    }
    await purgeUserRelatedData(
      { db },
      partnerRef.id,
      {
        authUid: (partnerData.auth_uid || "").toString().trim(),
        profileId: partnerPublicId,
      }
    );
    batch.delete(partnerRef);
  }

  await purgeUserRelatedData(
    { db },
    callerRef.id,
    {
      authUid: (callerData.auth_uid || "").toString().trim(),
      profileId: callerProfileId,
    }
  );
  batch.delete(callerRef);
  await batch.commit();

  return {
    success: true,
    storyId,
    partnerDocId,
    deletedCallerId: callerRef.id,
    matchSource: isAppMatch ? "mana_Vivaaha Vedika" : "external",
  };
});

/**
 * Daily purge of profiles whose 7-day grace period has ended.
 */
exports.processScheduledProfileDeletions = fnAsia.pubsub
  .schedule("every 24 hours")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("users")
      .where("deletion_requested", "==", true)
      .where("deletion_scheduled_at", "<=", now)
      .limit(200)
      .get();

    let purged = 0;
    for (const doc of snap.docs) {
      try {
        const data = doc.data() || {};
        await purgeUserRelatedData(
          { db },
          doc.id,
          {
            authUid: (data.auth_uid || "").toString().trim(),
            profileId: (data.profile_id || "").toString().trim(),
          }
        );
        await doc.ref.delete();
        purged += 1;
      } catch (e) {
        console.warn("processScheduledProfileDeletions: failed", doc.id, e?.message || e);
      }
    }
    console.log(`processScheduledProfileDeletions: purged ${purged} profile(s)`);
    return null;
  });

exports.adminDeleteUser = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const userId = (data?.user_id || "").toString().trim();
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "user_id is required.");
  }
  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};
  await purgeUserRelatedData(
    { db },
    userRef.id,
    {
      authUid: (userData.auth_uid || "").toString().trim(),
      profileId: (userData.profile_id || "").toString().trim(),
    }
  );
  await userRef.delete();
  return { success: true, user_id: userRef.id };
});

exports.adminApprovePaymentRequest = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const requestId = (data?.request_id || "").toString().trim();
  if (!requestId) {
    throw new functions.https.HttpsError("invalid-argument", "request_id is required.");
  }

  const requestRef = db.collection("payment_requests").doc(requestId);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Payment request not found.");
  }
  const reqData = requestSnap.data() || {};

  const userId = resolveTargetUserIdForPaymentRequest(reqData, data?.user_id);
  if (!userId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Could not resolve user from payment request (missing userDocId / user_id / uid)."
    );
  }

  const planDays = resolvePlanDaysForPaymentRequest(reqData, data?.plan_days);
  const notes =
    reqData.notes && typeof reqData.notes === "object" && !Array.isArray(reqData.notes)
      ? reqData.notes
      : {};
  const tier = (data?.tier || reqData.tier || notes.tier || "platinum")
    .toString()
    .trim()
    .toLowerCase();

  const userRef = await resolveUserDocRefForAdmin(userId);
  if (!userRef) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }

  const now = new Date();
  const expiry = new Date(now.getTime() + (planDays * 24 * 60 * 60 * 1000));
  const membershipPayload = buildMembershipPayload({
    tier: tier === "free" ? "free" : "platinum",
    startIso: now.toISOString(),
    expiryIso: tier === "free" ? null : expiry.toISOString(),
  });

  const batch = db.batch();
  batch.set(userRef, membershipPayload, { merge: true });
  batch.set(requestRef, {
    status: "approved",
    approved_at: admin.firestore.FieldValue.serverTimestamp(),
    approved_by: context.auth.uid,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();

  return { success: true, request_id: requestId, user_id: userRef.id };
});

exports.adminRejectPaymentRequest = fnAsia.https.onCall(async (data, context) => {
  await ensureCallerIsAdmin(context);
  const requestId = (data?.request_id || "").toString().trim();
  const reason = (data?.reason || "Rejected by admin").toString().trim();
  if (!requestId) {
    throw new functions.https.HttpsError("invalid-argument", "request_id is required.");
  }
  await db.collection("payment_requests").doc(requestId).set({
    status: "rejected",
    rejection_reason: reason,
    rejected_at: admin.firestore.FieldValue.serverTimestamp(),
    rejected_by: context.auth.uid,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true, request_id: requestId };
});

// ─────────────────────────────────────────────
// PROFILE PHOTO PROXY — stream bytes after auth + permission checks
// Flutter: GET streamProfilePhoto?ownerId=...&variant=full|preview
// Never expose raw Cloudinary / Storage URLs to the client.
// ─────────────────────────────────────────────
const {
  createStreamProfilePhotoHandler,
} = require("./src/profilePhotoProxy");

exports.streamProfilePhoto = fnAsia
  .runWith({
    secrets: ["CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET"],
    timeoutSeconds: 60,
    memory: "512MB",
  })
  .https.onRequest(createStreamProfilePhotoHandler(db, getCloudinary()));
