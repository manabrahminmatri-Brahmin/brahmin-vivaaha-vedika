/**
 * Cascade-delete engagement data when a user profile is removed.
 * Used by marriage deletion, scheduled purge, and admin delete.
 */

const BATCH_LIMIT = 450;

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference[]} refs
 */
async function commitDeletes(db, refs) {
  const unique = [...new Map(refs.map((r) => [r.path, r])).values()];
  for (let i = 0; i < unique.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    unique.slice(i, i + BATCH_LIMIT).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
  return unique.length;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} collection
 * @param {string} field
 * @param {string} value
 */
async function deleteByField(db, collection, field, value) {
  const v = (value || "").toString().trim();
  if (!v) return 0;
  const snap = await db.collection(collection).where(field, "==", v).get();
  return commitDeletes(
    db,
    snap.docs.map((d) => d.ref)
  );
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} parentPath e.g. youLiked/{userId}
 */
async function deleteAllSubdocs(db, parentRef, subName) {
  const snap = await parentRef.collection(subName).get();
  return commitDeletes(
    db,
    snap.docs.map((d) => d.ref)
  );
}

/**
 * Remove likes + legacy mirror docs for every identity alias of the deleted user.
 * @param {FirebaseFirestore.Firestore} db
 * @param {Set<string>} ids user doc id, auth uid, profile id
 */
async function purgeLikesForUser(db, ids) {
  const idList = [...ids].filter(Boolean);
  if (!idList.length) return { likes: 0, mirrors: 0 };

  const likeRefs = new Map();
  const mirrorRefs = [];

  const fields = ["from_user_id", "to_user_id", "fromUserId", "toUserId"];

  for (const id of idList) {
    for (const field of fields) {
      const snap = await db.collection("likes").where(field, "==", id).get();
      for (const doc of snap.docs) {
        likeRefs.set(doc.ref.path, doc.ref);
        const row = doc.data() || {};
        const from = (row.from_user_id || row.fromUserId || "").toString().trim();
        const to = (row.to_user_id || row.toUserId || "").toString().trim();
        if (from && to) {
          mirrorRefs.push(
            db.collection("youLiked").doc(from).collection("users").doc(to)
          );
          mirrorRefs.push(
            db.collection("likedYou").doc(to).collection("users").doc(from)
          );
        }
      }
    }
    // Doc ids like {from}_{to} when field queries miss legacy rows.
    for (const id2 of idList) {
      if (id === id2) continue;
      const a = `${id}_${id2}`;
      const b = `${id2}_${id}`;
      for (const docId of [a, b]) {
        const ref = db.collection("likes").doc(docId);
        const snap = await ref.get();
        if (snap.exists) {
          likeRefs.set(ref.path, ref);
          const row = snap.data() || {};
          const from = (row.from_user_id || row.fromUserId || id).toString().trim();
          const to = (row.to_user_id || row.toUserId || id2).toString().trim();
          mirrorRefs.push(
            db.collection("youLiked").doc(from).collection("users").doc(to)
          );
          mirrorRefs.push(
            db.collection("likedYou").doc(to).collection("users").doc(from)
          );
        }
      }
    }
  }

  const mirrors = await commitDeletes(db, mirrorRefs);
  const likes = await commitDeletes(db, [...likeRefs.values()]);

  let ownedMirrors = 0;
  for (const id of idList) {
    ownedMirrors += await deleteAllSubdocs(
      db,
      db.collection("youLiked").doc(id),
      "users"
    );
    try {
      await db.collection("youLiked").doc(id).delete();
    } catch (_) {
      /* optional parent doc */
    }
    ownedMirrors += await deleteAllSubdocs(
      db,
      db.collection("likedYou").doc(id),
      "users"
    );
    try {
      await db.collection("likedYou").doc(id).delete();
    } catch (_) {
      /* optional */
    }
  }

  return { likes, mirrors: mirrors + ownedMirrors };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {Set<string>} ids
 */
async function purgeInterestsForUser(db, ids) {
  let total = 0;
  const fields = ["from_user_id", "to_user_id", "fromUserId", "toUserId"];
  for (const id of ids) {
    for (const field of fields) {
      total += await deleteByField(db, "interests", field, id);
    }
  }
  return total;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {Set<string>} ids
 */
async function purgeChatsForUser(db, ids) {
  const chatRefs = new Map();
  const messageRefs = [];

  for (const id of ids) {
    const snap = await db
      .collection("chats")
      .where("participants", "array-contains", id)
      .get();
    for (const doc of snap.docs) {
      chatRefs.set(doc.ref.path, doc.ref);
      const msgs = await doc.ref.collection("messages").get();
      msgs.docs.forEach((m) => messageRefs.push(m.ref));
    }
  }

  const messages = await commitDeletes(db, messageRefs);
  const chats = await commitDeletes(db, [...chatRefs.values()]);
  return { chats, messages };
}

/**
 * @param {object} ctx
 * @param {FirebaseFirestore.Firestore} ctx.db
 * @param {string} userDocId users/{id}
 * @param {{ authUid?: string, profileId?: string }} [meta]
 */
async function purgeUserRelatedData(ctx, userDocId, meta = {}) {
  const db = ctx.db;
  const uid = (userDocId || "").toString().trim();
  if (!uid) return { skipped: true };

  const ids = new Set([uid]);
  const authUid = (meta.authUid || "").toString().trim();
  const profileId = (meta.profileId || "").toString().trim();
  if (authUid) ids.add(authUid);
  if (profileId) ids.add(profileId);

  const summary = {};

  summary.likes = await purgeLikesForUser(db, ids);
  summary.interests = await purgeInterestsForUser(db, ids);

  const viewFields = [
    "viewer_user_id",
    "viewed_user_id",
    "viewed_profile_id",
    "viewer_id",
    "from_user_id",
    "from_user",
  ];
  summary.profile_views = 0;
  for (const id of ids) {
    for (const field of viewFields) {
      summary.profile_views += await deleteByField(db, "profile_views", field, id);
    }
  }

  const notifFields = [
    "user_id",
    "from_user_id",
    "to_user_id",
    "to_user",
    "receiver_user_id",
  ];
  summary.notifications = 0;
  for (const id of ids) {
    for (const field of notifFields) {
      summary.notifications += await deleteByField(db, "notifications", field, id);
    }
  }

  const photoFields = [
    "from_user_id",
    "to_user_id",
    "to_profile_id",
    "fromUserId",
    "toUserId",
  ];
  summary.photo_requests = 0;
  for (const id of ids) {
    for (const field of photoFields) {
      summary.photo_requests += await deleteByField(db, "photo_requests", field, id);
    }
  }

  const reqFields = [
    "requester_id",
    "owner_id",
    "requester_auth_uid",
    "owner_auth_uid",
    "requesterId",
    "ownerId",
  ];
  summary.birth_requests = 0;
  summary.community_reference_requests = 0;
  for (const id of ids) {
    for (const field of reqFields) {
      summary.birth_requests += await deleteByField(db, "birth_requests", field, id);
      summary.community_reference_requests += await deleteByField(
        db,
        "community_reference_requests",
        field,
        id
      );
    }
  }

  summary.community_reference_access = 0;
  for (const id of ids) {
    summary.community_reference_access += await deleteByField(
      db,
      "community_reference_access",
      "user_id",
      id
    );
    summary.community_reference_access += await deleteByField(
      db,
      "community_reference_access",
      "granted_to_user_id",
      id
    );
  }

  summary.blocks = 0;
  for (const id of ids) {
    summary.blocks += await deleteByField(db, "blocks", "blockerId", id);
    summary.blocks += await deleteByField(db, "blocks", "blockedId", id);
  }

  summary.chats = await purgeChatsForUser(db, ids);

  summary.support_threads = 0;
  for (const id of ids) {
    summary.support_threads += await deleteByField(db, "support_threads", "user_id", id);
    summary.support_threads += await deleteByField(db, "support_threads", "member_user_id", id);
  }

  summary.success_stories = 0;
  for (const id of ids) {
    summary.success_stories += await deleteByField(db, "success_stories", "user_id", id);
    summary.success_stories += await deleteByField(
      db,
      "success_stories",
      "partner_user_id",
      id
    );
    summary.success_stories += await deleteByField(
      db,
      "success_stories",
      "created_by_user_id",
      id
    );
  }

  summary.reports = 0;
  for (const id of ids) {
    summary.reports += await deleteByField(db, "reports", "reporterId", id);
    summary.reports += await deleteByField(db, "reports", "reportedId", id);
    summary.reports += await deleteByField(db, "reports", "reporter_id", id);
    summary.reports += await deleteByField(db, "reports", "reported_id", id);
  }

  if (authUid) {
    try {
      await db.collection("auth_uid_bridge").doc(authUid).delete();
    } catch (_) {
      /* ignore */
    }
  }

  try {
    await db.collection("userMeta").doc(uid).delete();
  } catch (_) {
    /* ignore */
  }

  try {
    await db.collection("user_online").doc(uid).delete();
  } catch (_) {
    /* ignore */
  }

  console.log("purgeUserRelatedData", uid, JSON.stringify(summary));
  return summary;
}

function userDataIsActive(data) {
  if (!data || typeof data !== "object") return false;
  if (data.is_deleted === true) return false;
  if (data.deletion_requested === true) return false;
  const status = (data.status || "").toString().toLowerCase();
  return !["deleted", "inactive", "suspended", "banned"].includes(status);
}

async function userProfileIsActive(db, rawId) {
  const id = (rawId || "").toString().trim();
  if (!id) return false;

  const byDoc = await db.collection("users").doc(id).get();
  if (byDoc.exists && userDataIsActive(byDoc.data())) return true;

  const byPid = await db
    .collection("users")
    .where("profile_id", "==", id)
    .limit(1)
    .get();
  if (!byPid.empty && userDataIsActive(byPid.docs[0].data())) return true;

  const byAuth = await db
    .collection("users")
    .where("auth_uid", "==", id)
    .limit(1)
    .get();
  if (!byAuth.empty && userDataIsActive(byAuth.docs[0].data())) return true;

  return false;
}

/**
 * Remove profile_views on [ownerIds] where the viewer account no longer exists.
 */
async function pruneStaleProfileViewsForOwnerIds(db, ownerIds) {
  const ids = [
    ...new Set(
      (ownerIds || [])
        .map((x) => (x || "").toString().trim())
        .filter(Boolean)
    ),
  ];
  if (!ids.length) return 0;

  const refs = new Map();
  const viewedFields = ["viewed_user_id", "viewed_profile_id"];

  for (const id of ids) {
    for (const field of viewedFields) {
      const snap = await db.collection("profile_views").where(field, "==", id).get();
      for (const doc of snap.docs) {
        const row = doc.data() || {};
        const viewer = (row.viewer_user_id ||
          row.viewer_id ||
          row.from_user_id ||
          row.from_user ||
          "")
          .toString()
          .trim();
        if (!viewer) {
          refs.set(doc.ref.path, doc.ref);
          continue;
        }
        const active = await userProfileIsActive(db, viewer);
        if (!active) refs.set(doc.ref.path, doc.ref);
      }
    }
  }

  return commitDeletes(db, [...refs.values()]);
}

const PENDING_STATUS = "pending";

/**
 * Delete pending birth/community/photo requests on [ownerIds] when requester deleted.
 */
async function pruneStaleAccessRequestsForOwnerIds(db, ownerIds) {
  const ids = [
    ...new Set(
      (ownerIds || [])
        .map((x) => (x || "").toString().trim())
        .filter(Boolean)
    ),
  ];
  if (!ids.length) return 0;

  const refs = new Map();
  const ownerFields = ["owner_id", "owner_auth_uid"];
  const accessCollections = ["birth_requests", "community_reference_requests"];

  for (const id of ids) {
    for (const coll of accessCollections) {
      for (const field of ownerFields) {
        const snap = await db
          .collection(coll)
          .where(field, "==", id)
          .where("status", "==", PENDING_STATUS)
          .get();
        for (const doc of snap.docs) {
          const row = doc.data() || {};
          const requester = (row.requester_id ||
            row.requester_auth_uid ||
            row.requesterId ||
            "")
            .toString()
            .trim();
          if (!requester) {
            refs.set(doc.ref.path, doc.ref);
            continue;
          }
          if (!(await userProfileIsActive(db, requester))) {
            refs.set(doc.ref.path, doc.ref);
          }
        }
      }
    }

    for (const field of ["to_user_id", "to_profile_id"]) {
      const snap = await db
        .collection("photo_requests")
        .where(field, "==", id)
        .where("status", "==", PENDING_STATUS)
        .get();
      for (const doc of snap.docs) {
        const row = doc.data() || {};
        const from = (row.from_user_id || row.fromUserId || "").toString().trim();
        if (!from) {
          refs.set(doc.ref.path, doc.ref);
          continue;
        }
        if (!(await userProfileIsActive(db, from))) {
          refs.set(doc.ref.path, doc.ref);
        }
      }
    }
  }

  return commitDeletes(db, [...refs.values()]);
}

/**
 * Delete pending requests sent by [requesterIds] when owner/recipient deleted.
 */
async function pruneStaleAccessRequestsForRequesterIds(db, requesterIds) {
  const ids = [
    ...new Set(
      (requesterIds || [])
        .map((x) => (x || "").toString().trim())
        .filter(Boolean)
    ),
  ];
  if (!ids.length) return 0;

  const refs = new Map();
  const requesterFields = ["requester_id", "requester_auth_uid"];
  const accessCollections = ["birth_requests", "community_reference_requests"];

  for (const id of ids) {
    for (const coll of accessCollections) {
      for (const field of requesterFields) {
        const snap = await db
          .collection(coll)
          .where(field, "==", id)
          .where("status", "==", PENDING_STATUS)
          .get();
        for (const doc of snap.docs) {
          const row = doc.data() || {};
          const owner = (row.owner_id ||
            row.owner_auth_uid ||
            row.ownerId ||
            "")
            .toString()
            .trim();
          if (!owner) {
            refs.set(doc.ref.path, doc.ref);
            continue;
          }
          if (!(await userProfileIsActive(db, owner))) {
            refs.set(doc.ref.path, doc.ref);
          }
        }
      }
    }

    for (const field of ["from_user_id", "fromUserId"]) {
      const snap = await db
        .collection("photo_requests")
        .where(field, "==", id)
        .where("status", "==", PENDING_STATUS)
        .get();
      for (const doc of snap.docs) {
        const row = doc.data() || {};
        const to = (row.to_user_id ||
          row.to_profile_id ||
          row.toUserId ||
          "")
          .toString()
          .trim();
        if (!to) {
          refs.set(doc.ref.path, doc.ref);
          continue;
        }
        if (!(await userProfileIsActive(db, to))) {
          refs.set(doc.ref.path, doc.ref);
        }
      }
    }
  }

  return commitDeletes(db, [...refs.values()]);
}

module.exports = {
  purgeUserRelatedData,
  pruneStaleProfileViewsForOwnerIds,
  pruneStaleAccessRequestsForOwnerIds,
  pruneStaleAccessRequestsForRequesterIds,
  userProfileIsActive,
};
