/**
 * Seed indian_pincodes/{pin} from India Post API (run locally or as admin job).
 *
 * Usage (from functions/ with credentials):
 *   node ../scripts/sync_indian_pincodes.js 560001 500001
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS or firebase login for Admin SDK.
 */
const admin = require("firebase-admin");
const {
  lookupIndianPincodePayload,
  normalizePin,
} = require("../functions/src/lookupIndianPincode");

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

async function syncPin(pin) {
  const cleaned = normalizePin(pin);
  if (cleaned.length !== 6) {
    console.warn("Skip invalid pin:", pin);
    return;
  }
  const payload = await lookupIndianPincodePayload(cleaned, { db });
  if (!payload.success) {
    console.warn(`Failed ${cleaned}:`, payload.error);
    return;
  }
  await db.collection("indian_pincodes").doc(cleaned).set(
    {
      ...payload,
      synced_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { merge: true }
  );
  console.log(`Synced ${cleaned} (${payload.offices?.length || 0} offices)`);
}

async function main() {
  const pins = process.argv.slice(2);
  if (!pins.length) {
    console.log("Provide one or more 6-digit PIN codes.");
    process.exit(1);
  }
  for (const p of pins) {
    await syncPin(p);
  }
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
