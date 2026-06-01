const functions = require("firebase-functions");
const { secureHttpsOnCall } = require("./callable_security");
const { MATRIMONY_LIMITS } = require("./rate_limit");
const { normalizeAccessStatus } = require("./access_request_lifecycle");

const DENY_RESEND_COOLDOWN_MS = 24 * 60 * 60 * 1000;

/**
 * @param {{ db: FirebaseFirestore.Firestore, admin: typeof import('firebase-admin'), fnAsia: import('firebase-functions').region.RegionBuilder, deps: object }} ctx
 */
function createCreatePhotoRequestCallable(ctx) {
  const { db, admin, fnAsia } = ctx;
  const resolveCallerProfileRef = ctx.deps.resolveCallerProfileRef;
  const resolveUserDocRefByAnyId = ctx.deps.resolveUserDocRefByAnyId;
  const rateLimiter = ctx.deps.rateLimiter;
  const isBlockedPair = ctx.deps.isBlockedPair;
  const writeSecurityAudit = ctx.deps.writeSecurityAudit;

  return secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }

    await rateLimiter.consume(
      context.auth.uid,
      "createPhotoRequest",
      MATRIMONY_LIMITS.createPhotoRequest
    );

    const targetHint = (
      data?.toUserId ||
      data?.targetUserId ||
      data?.to_user_id ||
      data?.toProfileId ||
      data?.targetProfileId ||
      data?.to_profile_id ||
      ""
    )
      .toString()
      .trim();
    const requesterHint = (data?.fromUserId || data?.requesterId || data?.from_user_id || "")
      .toString()
      .trim();

    if (!targetHint) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "toUserId is required."
      );
    }

    const callerRef = await resolveCallerProfileRef(context, requesterHint);
    if (!callerRef) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Could not resolve your profile."
      );
    }

    const fromUserId = callerRef.id;

    // Bind requester auth_uid before write (matches birth/community callables).
    await db.collection("users").doc(fromUserId).set(
      {
        auth_uid: context.auth.uid,
        auth_uid_synced_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    if (!resolveUserDocRefByAnyId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Photo request resolver is not configured."
      );
    }
    const targetRef = await resolveUserDocRefByAnyId(targetHint);
    if (!targetRef) {
      throw new functions.https.HttpsError("not-found", "Target user not found.");
    }
    const targetUserId = targetRef.id;

    if (fromUserId === targetUserId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Cannot request photos from yourself."
      );
    }

    if (await isBlockedPair(fromUserId, targetUserId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Photo request blocked due to member block."
      );
    }

    const requestId = `${fromUserId}_${targetUserId}`;
    const ref = db.collection("photo_requests").doc(requestId);
    const existing = await ref.get();
    if (existing.exists) {
      const row = existing.data() || {};
      const status = normalizeAccessStatus(row.status);
      if (status === "pending" || status === "granted") {
        return {
          success: true,
          requestId,
          status,
          duplicateIgnored: true,
        };
      }
      // Sender "Request Again" after revoke should restart the flow as pending.
      // Keep the original request doc id for audit continuity.
      if (status === "revoked" || status === "stopped") {
        await ref.set(
          {
            status: "pending",
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            lastTransition: `${status}->pending`,
            actorRole: "requester",
            actedBy: context.auth.uid,
          },
          { merge: true }
        );
        return {
          success: true,
          requestId,
          status: "pending",
          resent: true,
        };
      }
      if (status === "denied") {
        const deniedRaw = row.deniedAt || row.denied_at || row.responded_at;
        let deniedMs = null;
        if (typeof deniedRaw === "string") {
          deniedMs = Date.parse(deniedRaw);
        } else if (deniedRaw?.toMillis) {
          deniedMs = deniedRaw.toMillis();
        }
        if (deniedMs && Date.now() - deniedMs < DENY_RESEND_COOLDOWN_MS) {
          throw new functions.https.HttpsError(
            "resource-exhausted",
            "Please wait before sending another photo request."
          );
        }
      }
    }

    const [requesterSnap, targetSnap] = await Promise.all([
      db.collection("users").doc(fromUserId).get(),
      db.collection("users").doc(targetUserId).get(),
    ]);
    if (!targetSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Target user not found.");
    }

    const requester = requesterSnap.data() || {};
    const target = targetSnap.data() || {};
    const requesterProfile =
      requester.profile && typeof requester.profile === "object"
        ? requester.profile
        : {};
    const targetProfile =
      target.profile && typeof target.profile === "object" ? target.profile : {};

    const fromProfileId = (
      data?.fromProfileId ||
      data?.requesterProfileId ||
      requester.profile_id ||
      ""
    )
      .toString()
      .trim();
    const toProfileId = (data?.toProfileId || data?.targetProfileId || target.profile_id || "")
      .toString()
      .trim();

    const now = admin.firestore.FieldValue.serverTimestamp();
    const targetAuthUid = (target.auth_uid || "").toString().trim();

    const payload = {
      from_user_id: fromUserId,
      to_user_id: targetUserId,
      requester_auth_uid: context.auth.uid,
      owner_auth_uid: targetAuthUid,
      status: "pending",
      requestCreatedAt: existing.exists
        ? existing.data()?.requestCreatedAt ||
          existing.data()?.created_at ||
          now
        : now,
      created_at: existing.exists ? existing.data()?.created_at || now : now,
      updated_at: now,
      lastTransition: "->pending",
      actorRole: "requester",
      actedBy: context.auth.uid,
    };
    if (fromProfileId) payload.from_profile_id = fromProfileId;
    if (toProfileId) payload.to_profile_id = toProfileId;

    const firstName = (requester.first_name || requesterProfile.first_name || "").toString();
    const lastName = (requester.last_name || requesterProfile.last_name || "").toString();
    const city = (requester.city || requesterProfile.city || "").toString();
    const state = (requester.state || requesterProfile.state || "").toString();
    if (firstName) {
      payload.from_first_name = firstName;
      payload.requester_first_name = firstName;
    }
    if (lastName) {
      payload.from_last_name = lastName;
      payload.requester_last_name = lastName;
    }
    if (fromProfileId) payload.requester_profile_id = fromProfileId;
    if (city) payload.from_city = city;
    if (state) payload.from_state = state;
    payload.requester_id = fromUserId;

    await ref.set(payload, { merge: true });

    try {
      const requesterName = [firstName, lastName].filter(Boolean).join(" ").trim();
      const nowIso = new Date().toISOString();
      await db.collection("notifications").add({
        user_id: targetUserId,
        to_user: targetUserId,
        from_user: fromUserId,
        type: "photo_request",
        title: "Photo access request",
        body: `${requesterName || "A member"} requested to view your photo.`,
        message: `${requesterName || "A member"} requested to view your photo.`,
        related_profile_id: fromProfileId || fromUserId,
        related_user_id: fromUserId,
        request_doc_id: requestId,
        is_read: false,
        created_at: nowIso,
      });
    } catch (e) {
      console.warn("createPhotoRequest notification failed:", e?.message || e);
    }

    await writeSecurityAudit("photo_request_sent", {
      actor_user_id: fromUserId,
      actor_auth_uid: context.auth.uid,
      document_id: requestId,
      target_user_id: targetUserId,
    });

    return { success: true, requestId, status: "pending" };
  });
}

module.exports = { createCreatePhotoRequestCallable };
