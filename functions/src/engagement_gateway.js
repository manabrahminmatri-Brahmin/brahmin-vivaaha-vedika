const functions = require("firebase-functions");
const { secureHttpsOnCall } = require("./callable_security");
const { MATRIMONY_LIMITS } = require("./rate_limit");

const ENGAGEMENT_LIMITS = {
  recordProfileView: { windowMs: 60 * 60 * 1000, max: 120 },
  recordLike: { windowMs: 60 * 60 * 1000, max: 40 },
};

/**
 * @param {{ db: FirebaseFirestore.Firestore, admin: typeof import('firebase-admin'), fnAsia: import('firebase-functions').region.RegionBuilder, deps: object }} ctx
 */
function registerEngagementCallables(ctx) {
  const { db, admin, fnAsia } = ctx;
  const resolveCallerProfileRef = ctx.deps.resolveCallerProfileRef;
  const rateLimiter = ctx.deps.rateLimiter;
  const isBlockedPair = ctx.deps.isBlockedPair;

  function dayBucketUtc() {
    const d = new Date();
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, "0");
    const day = String(d.getUTCDate()).padStart(2, "0");
    return `${y}${m}${day}`;
  }

  const recordProfileView = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await rateLimiter.consume(
      context.auth.uid,
      "recordProfileView",
      ENGAGEMENT_LIMITS.recordProfileView
    );

    const viewedUserId = (data?.viewedUserId || data?.viewed_profile_id || "")
      .toString()
      .trim();
    if (!viewedUserId) {
      throw new functions.https.HttpsError("invalid-argument", "viewedUserId is required.");
    }

    const callerRef = await resolveCallerProfileRef(context, "");
    if (!callerRef) {
      throw new functions.https.HttpsError("permission-denied", "Profile not found.");
    }
    const viewerId = callerRef.id;
    if (viewerId === viewedUserId) {
      return { success: true, duplicateIgnored: true, reason: "self_view" };
    }

    if (await isBlockedPair(viewerId, viewedUserId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Profile view blocked."
      );
    }

    const bucket = dayBucketUtc();
    const viewDocId = `${viewerId}_${viewedUserId}_${bucket}`;
    const viewRef = db.collection("profile_views").doc(viewDocId);
    const existing = await viewRef.get();
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (existing.exists) {
      await viewRef.set({ viewed_at: now, updated_at: now }, { merge: true });
      return {
        success: true,
        viewId: viewDocId,
        duplicateIgnored: true,
      };
    }

    const batch = db.batch();
    batch.set(viewRef, {
      viewer_user_id: viewerId,
      viewed_profile_id: viewedUserId,
      viewed_user_id: viewedUserId,
      view_day: bucket,
      viewed_at: now,
      created_at: now,
      updated_at: now,
    });
    batch.set(
      db.collection("users").doc(viewerId),
      {
        profile_views_sent: admin.firestore.FieldValue.increment(1),
        last_active: now,
        updated_at: now,
      },
      { merge: true }
    );
    batch.set(
      db.collection("users").doc(viewedUserId),
      {
        profile_views_received: admin.firestore.FieldValue.increment(1),
        updated_at: now,
      },
      { merge: true }
    );
    await batch.commit();

    return { success: true, viewId: viewDocId, duplicateIgnored: false };
  });

  const recordLike = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await rateLimiter.consume(
      context.auth.uid,
      "recordLike",
      ENGAGEMENT_LIMITS.recordLike
    );

    const targetUserId = (data?.targetUserId || data?.toUserId || "").toString().trim();
    const action = (data?.action || "like").toString().trim().toLowerCase();
    const unlike = action === "unlike" || action === "remove";

    if (!targetUserId) {
      throw new functions.https.HttpsError("invalid-argument", "targetUserId is required.");
    }

    const callerRef = await resolveCallerProfileRef(context, "");
    if (!callerRef) {
      throw new functions.https.HttpsError("permission-denied", "Profile not found.");
    }
    const fromId = callerRef.id;
    if (fromId === targetUserId) {
      throw new functions.https.HttpsError("invalid-argument", "Cannot like yourself.");
    }

    if (await isBlockedPair(fromId, targetUserId)) {
      throw new functions.https.HttpsError("permission-denied", "Like blocked.");
    }

    const likeId = `${fromId}_${targetUserId}`;
    const likeRef = db.collection("likes").doc(likeId);
    const likeSnap = await likeRef.get();
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (!unlike) {
      if (likeSnap.exists) {
        return { success: true, likeId, liked: true, duplicateIgnored: true };
      }
      const batch = db.batch();
      batch.set(likeRef, {
        from_user_id: fromId,
        to_user_id: targetUserId,
        created_at: now,
        updated_at: now,
      });
      batch.set(
        db.collection("users").doc(fromId),
        { likes_sent: admin.firestore.FieldValue.increment(1), updated_at: now },
        { merge: true }
      );
      batch.set(
        db.collection("users").doc(targetUserId),
        { likes_received: admin.firestore.FieldValue.increment(1), updated_at: now },
        { merge: true }
      );
      await batch.commit();
      return { success: true, likeId, liked: true, duplicateIgnored: false };
    }

    if (!likeSnap.exists) {
      return { success: true, likeId, liked: false, duplicateIgnored: true };
    }

    const batch = db.batch();
    batch.delete(likeRef);
    batch.set(
      db.collection("users").doc(fromId),
      { likes_sent: admin.firestore.FieldValue.increment(-1), updated_at: now },
      { merge: true }
    );
    batch.set(
      db.collection("users").doc(targetUserId),
      { likes_received: admin.firestore.FieldValue.increment(-1), updated_at: now },
      { merge: true }
    );
    await batch.commit();
    return { success: true, likeId, liked: false, duplicateIgnored: false };
  });

  return { recordProfileView, recordLike };
}

module.exports = { registerEngagementCallables, ENGAGEMENT_LIMITS };
