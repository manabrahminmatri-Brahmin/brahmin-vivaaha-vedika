/**
 * Deletes birth_requests / community_reference_requests with invalid or legacy auth-UID-shaped IDs.
 *
 * Run: node scripts/clean_stale_requests.js [--dry-run]
 */

const admin = require("firebase-admin");

let serviceAccount;
try {
  serviceAccount = require("./serviceAccountKey.json");
} catch (e) {
  console.error("Missing scripts/serviceAccountKey.json");
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const dryRun = process.argv.includes("--dry-run");

/** Heuristic: Firebase Auth UIDs are typically 28 chars alphanumeric. */
function looksLikeAuthUid(id) {
  const s = (id || "").toString().trim();
  return s.length >= 28 && /^[a-zA-Z0-9]+$/.test(s);
}

async function cleanCollection(collectionName) {
  const snap = await db.collection(collectionName).get();
  let deleted = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const requesterId = (data.requester_id || "").toString().trim();
    const ownerId = (data.owner_id || "").toString().trim();

    const invalid =
      !requesterId ||
      !ownerId ||
      looksLikeAuthUid(requesterId) ||
      looksLikeAuthUid(ownerId);

    if (invalid) {
      console.log(
        `${dryRun ? "would delete" : "deleting"} ${collectionName}/${doc.id} requester=${requesterId} owner=${ownerId}`
      );
      if (!dryRun) {
        batch.delete(doc.ref);
        batchCount++;
        deleted++;
        if (batchCount >= 400) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      } else {
        deleted++;
      }
    }
  }
  if (!dryRun && batchCount > 0) await batch.commit();
  console.log(`Cleaned ${deleted} docs from ${collectionName}${dryRun ? " (dry-run)" : ""}`);
}

async function main() {
  await cleanCollection("birth_requests");
  await cleanCollection("community_reference_requests");
  console.log("✅ Cleanup complete");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
