/**
 * One-time migration: stamp users/{doc}.auth_uid from Firebase Auth users.
 *
 * Prerequisites:
 *   Place service account JSON next to this file as serviceAccountKey.json (do not commit).
 *
 * Run from repo root:
 *   node scripts/fix_auth_uid.js
 */

const admin = require("firebase-admin");

let serviceAccount;
try {
  serviceAccount = require("./serviceAccountKey.json");
} catch (e) {
  console.error(
    "Missing scripts/serviceAccountKey.json — download from Firebase Console → Project settings → Service accounts."
  );
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();
const auth = admin.auth();

const normalizePhone = (raw) =>
  (raw || "").toString().replace(/\D/g, "").replace(/^91/, "");

async function fixAuthUids() {
  let pageToken;
  let fixed = 0;
  let skipped = 0;
  let notFound = 0;

  do {
    const result = await auth.listUsers(1000, pageToken);
    for (const user of result.users) {
      const phone = normalizePhone(user.phoneNumber || "");
      if (!phone) {
        skipped++;
        continue;
      }

      const directSnap = await db.collection("users").doc(user.uid).get();
      if (directSnap.exists) {
        await directSnap.ref.set(
          { auth_uid: user.uid, updated_at: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        console.log(`✅ Direct doc: ${user.uid}`);
        fixed++;
        continue;
      }

      const variants = [phone, `91${phone}`, `+91${phone}`];
      let matched = null;
      for (const v of variants) {
        const snap = await db
          .collection("users")
          .where("mobile_number", "==", v)
          .limit(1)
          .get();
        if (!snap.empty) {
          matched = snap.docs[0];
          break;
        }
      }

      if (matched) {
        await matched.ref.set(
          { auth_uid: user.uid, updated_at: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        console.log(`✅ Phone match: ${user.uid} → doc ${matched.id}`);
        fixed++;
      } else {
        console.warn(`❌ No user doc for Auth UID ${user.uid} phone ${phone}`);
        notFound++;
      }
    }
    pageToken = result.pageToken;
  } while (pageToken);

  console.log(`\n=== Done: fixed=${fixed} skipped=${skipped} notFound=${notFound} ===`);
}

fixAuthUids().catch((err) => {
  console.error(err);
  process.exit(1);
});
