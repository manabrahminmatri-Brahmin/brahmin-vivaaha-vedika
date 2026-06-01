/**
 * Shared matrimony helpers for Cloud Functions.
 * @param {FirebaseFirestore.Firestore} db
 */
function createMatrimonyShared(db) {
  async function isBlockedPair(userA, userB) {
    const a = (userA || "").toString().trim();
    const b = (userB || "").toString().trim();
    if (!a || !b || a === b) return false;
    const id1 = `${a}_${b}`;
    const id2 = `${b}_${a}`;
    const [s1, s2] = await Promise.all([
      db.collection("blocks").doc(id1).get(),
      db.collection("blocks").doc(id2).get(),
    ]);
    return s1.exists || s2.exists;
  }

  return { isBlockedPair };
}

module.exports = { createMatrimonyShared };
