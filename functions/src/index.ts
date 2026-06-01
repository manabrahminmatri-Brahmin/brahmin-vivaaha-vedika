/**
 * CRITICAL SECURITY FIX: Changed from auto-activation to pending verification.
 * When a client creates `payment_requests/{id}` with status `pending`,
 * this function validates amount/plan and sets status to "pending_verification".
 * Premium is NOT automatically activated - admin must verify the UTR and approve.
 * Deploy: `cd functions && npm install && npm run deploy`
 * (requires Firebase Blaze + `firebase deploy --only functions`).
 */
import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions";

admin.initializeApp();
const db = admin.firestore();

/** Must match `MembershipPlan.plans` paid entries in lib/models/membership.dart */
// UPDATED: Prices synced with app - 1M=₹99, 3M=₹297, 6M=₹594, 12M=₹1188
const VALID_PLANS: ReadonlyArray<{
  days: number;
  price: number;
  tier: string;
}> = [
  {days: 30, price: 99, tier: "platinum"},
  {days: 90, price: 297, tier: "platinum"},
  {days: 180, price: 594, tier: "platinum"},
  {days: 365, price: 1188, tier: "platinum"},
];

function findPlan(days: number, amount: number, tier: string): (typeof VALID_PLANS)[0] | null {
  const t = (tier || "").toLowerCase().trim();
  if (t !== "platinum") return null;
  return VALID_PLANS.find((p) => p.days === days && p.price === amount) ?? null;
}

export const onPaymentRequestCreated = onDocumentCreated(
  {
    document: "payment_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const requestId = event.params.requestId as string;
    const data = snap.data() as Record<string, unknown>;
    const status = (data.status as string) || "";

    if (status !== "pending") {
      logger.info("Skip: not pending", {requestId, status});
      return;
    }

    const userId = data.user_id as string;
    const utr = String(data.utr || "").trim().toUpperCase();
    const planDays = Number(data.plan_days);
    const amount = Number(data.amount);
    const tier = String(data.tier || "");

    if (!userId || !utr || utr.length < 6) {
      await rejectRequest(requestId, "Missing user_id or invalid UTR");
      return;
    }

    const plan = findPlan(planDays, amount, tier);
    if (!plan) {
      await rejectRequest(
        requestId,
        `No matching plan for days=${planDays} amount=${amount} tier=${tier}`
      );
      return;
    }

    // Duplicate UTR (single-field query — no composite index needed)
    const dup = await db.collection("payment_requests").where("utr", "==", utr).get();
    const duplicateApproved = dup.docs.some(
      (d) => d.id !== requestId && (d.data().status as string) === "approved"
    );
    if (duplicateApproved) {
      await rejectRequest(requestId, "Duplicate UTR already used");
      return;
    }

    const userRef = db.collection("users").doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      await rejectRequest(requestId, "User document not found");
      return;
    }

    // SECURITY FIX: Do NOT auto-activate premium. Set to pending_verification for admin review.
    // The UTR (bank transaction reference) must be verified against actual bank records before approval.
    await snap.ref.update({
      status: "pending_verification",
      verified_plan_days: plan.days,
      verified_plan_price: plan.price,
      verified_plan_tier: plan.tier,
      submitted_at: admin.firestore.FieldValue.serverTimestamp(),
      note: "Payment submitted. Awaiting admin verification of UTR before premium activation.",
    });

    logger.info("Payment request pending verification", {userId, requestId, utr, plan});
  }
);

async function rejectRequest(requestId: string, note: string): Promise<void> {
  logger.warn("Payment request rejected", {requestId, note});
  await db.collection("payment_requests").doc(requestId).update({
    status: "rejected",
    approved_at: admin.firestore.FieldValue.serverTimestamp(),
    approved_by: "system_auto",
    note,
  });
}
