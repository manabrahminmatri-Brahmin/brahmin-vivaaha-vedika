/**
 * Shared privacy access request lifecycle helpers (photo, birth, community).
 */
const functions = require("firebase-functions");

const REQUEST_DOC_ID_RE = /^[a-zA-Z0-9_-]{3,128}$/;

/** Canonical statuses written by the server. */
const CANONICAL_STATUSES = new Set([
  "pending",
  "granted",
  "denied",
  "revoked",
  "stopped",
  "withdrawn",
]);

/**
 * Normalize legacy status strings to canonical values.
 * @param {unknown} raw
 * @returns {string}
 */
function normalizeAccessStatus(raw) {
  const s = (raw || "pending").toString().trim().toLowerCase();
  if (!s) return "pending";
  if (s === "approved" || s === "accepted") return "granted";
  if (s === "rejected" || s === "declined") return "denied";
  if (CANONICAL_STATUSES.has(s)) return s;
  return s;
}

/**
 * @param {string} requestId
 * @returns {string}
 */
function assertValidRequestDocId(requestId) {
  const id = (requestId || "").toString().trim();
  if (!REQUEST_DOC_ID_RE.test(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid requestId format."
    );
  }
  return id;
}

/**
 * Live photo access: read composite doc and require canonical granted status.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} viewerDocId
 * @param {string} ownerDocId
 */
async function isPhotoAccessGranted(db, viewerDocId, ownerDocId, viewerAuthUid) {
  const viewer = (viewerDocId || "").toString().trim();
  const owner = (ownerDocId || "").toString().trim();
  if (!viewer || !owner) return false;
  if (viewer === owner) return true;

  const isGrantedStatus = (raw) => normalizeAccessStatus(raw) === "granted";

  const requestId = `${viewer}_${owner}`;
  const snap = await db.collection("photo_requests").doc(requestId).get();
  if (snap.exists && isGrantedStatus(snap.data()?.status)) {
    return true;
  }

  const authUid = (viewerAuthUid || "").toString().trim();
  if (authUid) {
    const q = await db
      .collection("photo_requests")
      .where("requester_auth_uid", "==", authUid)
      .where("to_user_id", "==", owner)
      .limit(5)
      .get();
    for (const doc of q.docs) {
      if (isGrantedStatus(doc.data()?.status)) return true;
    }
  }
  return false;
}

/**
 * Merge audit fields for owner transitions.
 * @param {Record<string, unknown>} patch
 * @param {object} opts
 * @param {string} opts.fromStatus
 * @param {string} opts.toStatus
 * @param {string} opts.actorUid Firebase Auth uid
 * @param {string} opts.actorRole e.g. owner | requester | admin
 * @param {Record<string, unknown>} [opts.row]
 */
function applyTransitionAudit(patch, opts) {
  const fromStatus = normalizeAccessStatus(opts.fromStatus);
  const toStatus = normalizeAccessStatus(opts.toStatus);
  const row = opts.row || {};
  patch.status = toStatus;
  patch.lastTransition = `${fromStatus}->${toStatus}`;
  patch.actedBy = (opts.actorUid || "").toString();
  patch.actorRole = (opts.actorRole || "owner").toString();

  const created =
    row.requestCreatedAt ||
    row.request_created_at ||
    row.created_at ||
    row.createdAt;
  if (created && !row.requestCreatedAt) {
    patch.requestCreatedAt = created;
    patch.request_created_at = created;
  }

  return patch;
}

/**
 * In-app notification for requester after owner action.
 * @param {FirebaseFirestore.Firestore} db
 */
async function notifyRequesterOutcome(db, opts) {
  const requesterId = (opts.requesterId || "").toString().trim();
  if (!requesterId) return;

  const kind = (opts.kind || "").toString(); // photo | birth | community
  const outcome = normalizeAccessStatus(opts.outcome); // granted | denied | revoked
  const ownerName = (opts.ownerName || "Profile Owner").toString();
  const requestDocId = (opts.requestDocId || "").toString().trim();
  const ownerId = (opts.ownerId || "").toString().trim();
  const requesterProfileId = (opts.requesterProfileId || "").toString().trim();
  const nowIso = new Date().toISOString();

  const typeMap = {
    photo: {
      granted: "photo_request_granted",
      denied: "photo_request_denied",
      revoked: "photo_request_revoked",
      stopped: "photo_request_stopped",
    },
    birth: {
      granted: "birth_request_granted",
      denied: "birth_request_denied",
      revoked: "birth_request_revoked",
      stopped: "birth_request_stopped",
    },
    community: {
      granted: "community_reference_granted",
      denied: "community_reference_denied",
      revoked: "community_reference_revoked",
      stopped: "community_reference_stopped",
    },
  };

  const titleMap = {
    granted: "Access Granted",
    denied: "Request Declined",
    revoked: "Access Revoked",
    stopped: "Access Paused",
  };

  const bodyMap = {
    photo: {
      granted: `${ownerName} granted access to their private photo.`,
      denied: `${ownerName} declined your photo request.`,
      revoked: `${ownerName} revoked your photo access.`,
      stopped: `${ownerName} paused your photo access.`,
    },
    birth: {
      granted: `${ownerName} granted access to their birth details.`,
      denied: `${ownerName} declined your birth details request.`,
      revoked: `${ownerName} revoked your birth details access.`,
      stopped: `${ownerName} paused your birth details access.`,
    },
    community: {
      granted: "You can now view community references.",
      denied: `${ownerName} declined your community reference request.`,
      revoked: `${ownerName} revoked your community reference access.`,
      stopped: `${ownerName} paused your community reference access.`,
    },
  };

  const notifType = typeMap[kind]?.[outcome] || `${kind}_request_${outcome}`;
  const title = titleMap[outcome] || "Privacy request update";
  const body =
    bodyMap[kind]?.[outcome] || `${ownerName} updated your privacy request.`;

  try {
    await db.collection("notifications").add({
      user_id: requesterId,
      to_user: requesterId,
      from_user: ownerId,
      type: notifType,
      title,
      body,
      message: body,
      related_profile_id: requesterProfileId || requesterId,
      related_user_id: ownerId,
      request_doc_id: requestDocId,
      is_read: false,
      created_at: nowIso,
    });
  } catch (e) {
    console.warn("notifyRequesterOutcome failed:", e?.message || e);
  }
}

module.exports = {
  assertValidRequestDocId,
  normalizeAccessStatus,
  isPhotoAccessGranted,
  applyTransitionAudit,
  notifyRequesterOutcome,
  REQUEST_DOC_ID_RE,
};
