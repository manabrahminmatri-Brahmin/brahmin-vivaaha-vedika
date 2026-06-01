/**
 * Proxied profile photo streaming — never expose raw Cloudinary / Storage URLs to clients.
 *
 * GET /streamProfilePhoto?ownerId={firestoreUserDocId}&variant=full|preview
 * Authorization: Bearer <Firebase ID token>
 */

const admin = require("firebase-admin");
const { isPhotoAccessGranted } = require("./access_request_lifecycle");

const USERS = "users";

function readBool(doc, key, fallback = false) {
  if (!doc) return fallback;
  if (typeof doc[key] === "boolean") return doc[key];
  const nested = doc.profile;
  if (nested && typeof nested === "object" && typeof nested[key] === "boolean") {
    return nested[key];
  }
  return fallback;
}

function isPremiumUser(doc) {
  const tier = String(
    doc.membership_tier || doc.membership?.tier || "free"
  ).toLowerCase();
  if (tier !== "platinum" && tier !== "premium") return false;
  const exp =
    doc.membership_expiry_date ||
    doc.membership_expires_at ||
    doc.membership_json?.expiryDate;
  if (!exp) return false;
  const date = exp.toDate ? exp.toDate() : new Date(exp);
  return date.getTime() > Date.now();
}

function hideFromSearch(doc) {
  return readBool(doc, "privacy_hide_from_search");
}

function premiumOnlyVisibility(doc) {
  return readBool(doc, "privacy_premium_only_visibility");
}

function verifiedOnlyVisibility(doc) {
  return readBool(doc, "privacy_only_verified_users");
}

function hidePhotosUntilAccepted(doc) {
  return readBool(doc, "privacy_photo_visible_after_acceptance");
}

function blurPhotosForStrangers(doc) {
  return readBool(doc, "privacy_blur_photos_for_strangers");
}

function isPhotoPrivate(doc) {
  return (
    readBool(doc, "is_photo_private") ||
    readBool(doc, "isPhotoPrivate") ||
    readBool(doc, "photo_private")
  );
}

function isVerifiedUser(doc) {
  return (
    doc.is_verified === true ||
    doc.verified === true ||
    doc.profile?.is_verified === true
  );
}

function canViewerSeeProfile(viewer, owner) {
  if (viewer.id === owner.id) return true;
  if (hideFromSearch(owner.data)) return false;
  if (premiumOnlyVisibility(owner.data) && !isPremiumUser(viewer.data)) {
    return false;
  }
  if (verifiedOnlyVisibility(owner.data) && !isVerifiedUser(viewer.data)) {
    return false;
  }
  return true;
}

async function hasAcceptedInterest(db, viewerId, ownerId) {
  const oneWay = async (from, to) => {
    const snap = await db
      .collection("interests")
      .where("from_user_id", "==", from)
      .where("to_user_id", "==", to)
      .where("status", "==", "accepted")
      .limit(1)
      .get();
    return !snap.empty;
  };
  return (
    (await oneWay(viewerId, ownerId)) || (await oneWay(ownerId, viewerId))
  );
}

/** Live composite-doc check — revoked/denied cannot satisfy proxy auth. */
async function hasApprovedPhotoRequest(db, viewerId, ownerId, viewerAuthUid) {
  return isPhotoAccessGranted(db, viewerId, ownerId, viewerAuthUid);
}

/**
 * @returns {{ allow: boolean, status?: number, message?: string, transformation?: string }}
 */
async function evaluatePhotoStreamAccess(
  db,
  viewer,
  owner,
  variant,
  viewerAuthUid
) {
  if (!viewer || !owner) {
    return { allow: false, status: 404, message: "user_not_found" };
  }

  if (!canViewerSeeProfile(viewer, owner)) {
    return { allow: false, status: 403, message: "profile_not_visible" };
  }

  const ownerHasPhoto =
    Boolean(owner.data.photo_url || owner.data.profile_picture) ||
    Boolean(owner.data.profile?.profile_picture) ||
    Boolean(
      (owner.data.auth_uid || owner.data.authUid || "").toString().trim()
    );
  if (!ownerHasPhoto) {
    return { allow: false, status: 404, message: "no_photo" };
  }

  // Own photo — always allowed (full quality).
  if (viewer.id === owner.id) {
    return {
      allow: true,
      transformation: "c_fill,w_800,h_800,q_85,f_jpg",
    };
  }

  const privatePhoto = isPhotoPrivate(owner.data);

  if (privatePhoto) {
    const authUid =
      (viewerAuthUid || viewer.data.auth_uid || viewer.data.authUid || "")
        .toString()
        .trim();
    const granted = await hasApprovedPhotoRequest(
      db,
      viewer.id,
      owner.id,
      authUid
    );
    if (!granted) {
      return { allow: false, status: 403, message: "photo_private" };
    }
    return {
      allow: true,
      transformation:
        variant === "preview"
          ? "c_fill,w_320,h_320,q_75,f_jpg"
          : "c_fill,w_800,h_800,q_85,f_jpg",
    };
  }

  const accepted = await hasAcceptedInterest(db, viewer.id, owner.id);

  if (variant === "preview") {
    // Low-res / blurred teaser for free-tier UI overlays.
    if (hidePhotosUntilAccepted(owner.data) && !accepted) {
      return { allow: false, status: 403, message: "acceptance_required" };
    }
    return {
      allow: true,
      transformation: "c_fill,w_120,h_120,e_blur:1200,q_60,f_jpg",
    };
  }

  // variant === "full"
  if (!isPremiumUser(viewer.data)) {
    return { allow: false, status: 403, message: "premium_required" };
  }

  if (hidePhotosUntilAccepted(owner.data) && !accepted) {
    return { allow: false, status: 403, message: "acceptance_required" };
  }

  if (blurPhotosForStrangers(owner.data) && !accepted) {
    return { allow: false, status: 403, message: "connection_required" };
  }

  return {
    allow: true,
    transformation: "c_fill,w_800,h_800,q_85,f_jpg",
  };
}

async function resolveUserByAuthUid(db, authUid) {
  const uid = (authUid || "").toString().trim();
  if (!uid) return null;
  // Prefer users linked by auth_uid (legacy docs use random ids, not Auth uid).
  const q = await db
    .collection(USERS)
    .where("auth_uid", "==", uid)
    .limit(1)
    .get();
  if (!q.empty) {
    return { id: q.docs[0].id, data: q.docs[0].data() || {} };
  }
  const direct = await db.collection(USERS).doc(uid).get();
  if (direct.exists) {
    return { id: direct.id, data: direct.data() || {} };
  }
  return null;
}

function cloudinaryPublicIdForOwner(ownerData, ownerDocId, authUidFallback) {
  const authUid = String(
    ownerData.auth_uid || ownerData.authUid || authUidFallback || ownerDocId
  ).trim();
  return `profile_photos/${authUid}/profile`;
}

async function fetchCloudinaryBytes(cloudinary, publicId, transformation) {
  const url = cloudinary.url(publicId, {
    resource_type: "image",
    type: "upload",
    sign_url: true,
    secure: true,
    transformation,
  });

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`cloudinary_fetch_failed:${response.status}`);
  }
  const contentType = response.headers.get("content-type") || "image/jpeg";
  const buffer = Buffer.from(await response.arrayBuffer());
  return { buffer, contentType };
}

async function fetchFirebaseStorageBytes(ownerDocId, ownerData) {
  const bucket = admin.storage().bucket();
  const photoUrl = String(
    ownerData.photo_url ||
      ownerData.profile_picture ||
      ownerData.profile?.profile_picture ||
      ""
  );
  let filePath = `users/${ownerDocId}/photos/profile.jpg`;
  if (photoUrl.includes("/o/")) {
    try {
      const encoded = photoUrl.split("/o/")[1].split("?")[0];
      filePath = decodeURIComponent(encoded);
    } catch (_) {
      /* use default path */
    }
  }
  const file = bucket.file(filePath);
  const [buffer] = await file.download();
  return { buffer, contentType: "image/jpeg" };
}

async function fetchHttpPhotoBytes(photoUrl) {
  const url = String(photoUrl || "").trim();
  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    throw new Error("invalid_photo_url");
  }
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`http_photo_fetch_failed:${response.status}`);
  }
  const contentType = response.headers.get("content-type") || "image/jpeg";
  const buffer = Buffer.from(await response.arrayBuffer());
  return { buffer, contentType };
}

/**
 * Resolve owner photo bytes: Cloudinary (multiple public_id guesses) → HTTP URL → Storage.
 */
async function resolveOwnerPhotoPayload(cloudinary, owner, access) {
  const ownerData = owner.data || {};
  const photoUrl = String(
    ownerData.photo_url ||
      ownerData.profile_picture ||
      ownerData.profile?.profile_picture ||
      ""
  );
  const provider = String(ownerData.photo_provider || "cloudinary").toLowerCase();

  if (
    provider === "firebase" ||
    photoUrl.includes("firebasestorage.googleapis.com")
  ) {
    return fetchFirebaseStorageBytes(owner.id, ownerData);
  }

  const authUid = String(ownerData.auth_uid || ownerData.authUid || owner.id).trim();
  const publicIds = [
    cloudinaryPublicIdForOwner(ownerData, owner.id, authUid),
    `profile_photos/${authUid}/profile`,
    `profile_photos/${owner.id}/profile`,
  ].filter((id, idx, arr) => id && arr.indexOf(id) === idx);

  let lastErr;
  for (const publicId of publicIds) {
    try {
      return await fetchCloudinaryBytes(
        cloudinary,
        publicId,
        access.transformation
      );
    } catch (e) {
      lastErr = e;
      console.warn(
        "streamProfilePhoto: cloudinary miss",
        publicId,
        e?.message || e
      );
    }
  }

  if (photoUrl.startsWith("http://") || photoUrl.startsWith("https://")) {
    try {
      return await fetchHttpPhotoBytes(photoUrl);
    } catch (e) {
      lastErr = e;
      console.warn(
        "streamProfilePhoto: direct URL fetch failed",
        e?.message || e
      );
    }
  }

  try {
    return await fetchFirebaseStorageBytes(owner.id, ownerData);
  } catch (e) {
    lastErr = e;
  }

  throw lastErr || new Error("all_photo_sources_failed");
}

function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
}

/**
 * @param {import('firebase-admin').firestore.Firestore} db
 * @param {typeof import('cloudinary').v2} cloudinary
 */
function createStreamProfilePhotoHandler(db, cloudinary) {
  return async (req, res) => {
    setCors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "GET") {
      res.status(405).send("Method not allowed");
      return;
    }

    const authHeader = String(req.headers.authorization || "");
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      res.status(401).json({ error: "missing_auth" });
      return;
    }

    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(match[1]);
    } catch (e) {
      console.warn("streamProfilePhoto: invalid token", e?.message);
      res.status(401).json({ error: "invalid_token" });
      return;
    }

    const ownerId = String(req.query.ownerId || req.query.ownerUserId || "").trim();
    if (!ownerId) {
      res.status(400).json({ error: "missing_owner_id" });
      return;
    }

    const variant = String(req.query.variant || "full").toLowerCase() === "preview"
      ? "preview"
      : "full";

    try {
      const viewer = await resolveUserByAuthUid(db, decoded.uid);
      const ownerSnap = await db.collection(USERS).doc(ownerId).get();
      if (!ownerSnap.exists) {
        res.status(404).json({ error: "owner_not_found" });
        return;
      }
      const owner = { id: ownerSnap.id, data: ownerSnap.data() || {} };

      const access = await evaluatePhotoStreamAccess(
        db,
        viewer,
        owner,
        variant,
        decoded.uid
      );
      if (!access.allow) {
        res.status(access.status || 403).json({ error: access.message || "forbidden" });
        return;
      }

      const payload = await resolveOwnerPhotoPayload(cloudinary, owner, access);

      res.set("Content-Type", payload.contentType);
      res.set("Cache-Control", "private, no-store, max-age=0");
      res.set("X-Content-Type-Options", "nosniff");
      res.set("X-Photo-Proxy", "1");
      res.status(200).send(payload.buffer);
    } catch (e) {
      console.error("streamProfilePhoto error:", e?.message || e);
      res.status(502).json({ error: "upstream_fetch_failed" });
    }
  };
}

module.exports = {
  createStreamProfilePhotoHandler,
  evaluatePhotoStreamAccess,
  readBool,
  isPremiumUser,
};
