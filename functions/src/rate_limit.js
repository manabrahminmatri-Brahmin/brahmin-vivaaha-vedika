const functions = require("firebase-functions");

/**
 * Firestore-backed sliding-window rate limiter (per auth uid + action).
 * @param {FirebaseFirestore.Firestore} db
 * @param {typeof import('firebase-admin')} admin
 */
function createRateLimiter(db, admin) {
  /**
   * @param {string} uid Firebase Auth uid
   * @param {string} action Logical action key
   * @param {{ windowMs?: number, max?: number }} limits
   */
  async function consume(uid, action, limits = {}) {
    const authUid = (uid || "").toString().trim();
    const actionKey = (action || "").toString().trim();
    if (!authUid || !actionKey) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }

    const windowMs = Number(limits.windowMs) > 0 ? Number(limits.windowMs) : 60_000;
    const max = Number(limits.max) > 0 ? Number(limits.max) : 10;
    const now = Date.now();
    const docId = `${actionKey}_${authUid}`;
    const ref = db.collection("rate_limits").doc(docId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() || {} : {};
      let windowStart = Number(data.window_start_ms) || 0;
      let count = Number(data.count) || 0;

      if (!windowStart || now - windowStart > windowMs) {
        windowStart = now;
        count = 0;
      }

      count += 1;
      if (count > max) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Too many requests. Please wait and try again."
        );
      }

      tx.set(
        ref,
        {
          uid: authUid,
          action: actionKey,
          count,
          window_start_ms: windowStart,
          window_ms: windowMs,
          max,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });
  }

  return { consume };
}

/** Default limits for matrimony callables. */
const MATRIMONY_LIMITS = {
  createOrResendInterest: { windowMs: 60 * 60 * 1000, max: 30 },
  transitionInterestStatus: { windowMs: 60 * 1000, max: 40 },
  createPhotoRequest: { windowMs: 15 * 60 * 1000, max: 5 },
  transitionPhotoRequest: { windowMs: 60 * 1000, max: 40 },
  privacyRevokeAccess: { windowMs: 60 * 60 * 1000, max: 30 },
  sendBirthRequest: { windowMs: 24 * 60 * 60 * 1000, max: 20 },
  sendCommunityRequest: { windowMs: 24 * 60 * 60 * 1000, max: 20 },
  transitionBirthRequestStatus: { windowMs: 60 * 1000, max: 40 },
  transitionCommunityRequestStatus: { windowMs: 60 * 1000, max: 40 },
  createChatRoom: { windowMs: 60 * 60 * 1000, max: 20 },
  unlockContact: { windowMs: 60 * 60 * 1000, max: 25 },
  validatePremiumAccess: { windowMs: 60 * 1000, max: 60 },
  ensureSupportThread: { windowMs: 60 * 60 * 1000, max: 10 },
  sendSupportMessage: { windowMs: 60 * 1000, max: 30 },
  markSupportThreadRead: { windowMs: 60 * 1000, max: 60 },
};

module.exports = { createRateLimiter, MATRIMONY_LIMITS };
