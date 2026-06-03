/**
 * When a client creates payment_requests/{id} with status pending,
 * validate amount/plan and set status to pending_verification.
 * Premium is NOT auto-activated — admin must verify the UTR and approve.
 */
const admin = require("firebase-admin");

/** Must match MembershipPlan.plans paid entries in lib/models/membership.dart */
const VALID_PLANS = [
  { days: 30, price: 99, tier: "platinum" },
  { days: 90, price: 297, tier: "platinum" },
  { days: 180, price: 594, tier: "platinum" },
  { days: 365, price: 1188, tier: "platinum" },
];

function findPlan(days, amount, tier) {
  const t = (tier || "").toLowerCase().trim();
  if (t !== "platinum") return null;
  return (
    VALID_PLANS.find((p) => {
      if (p.days !== days) return false;
      if (Math.abs(p.price - amount) < 0.01) return true;
      const withGst = Math.round(p.price * 1.18 * 100) / 100;
      return Math.abs(withGst - amount) < 0.05;
    }) || null
  );
}

/**
 * @param {import("firebase-functions").region.RuntimeOptions} fnAsia
 * @param {{ db: FirebaseFirestore.Firestore }} deps
 */
function createOnPaymentRequestCreatedTrigger(fnAsia, { db }) {
  async function rejectRequest(requestId, note) {
    console.warn("Payment request rejected", { requestId, note });
    await db.collection("payment_requests").doc(requestId).update({
      status: "rejected",
      approved_at: admin.firestore.FieldValue.serverTimestamp(),
      approved_by: "system_auto",
      note,
    });
  }

  return fnAsia.firestore
    .document("payment_requests/{requestId}")
    .onCreate(async (snap, context) => {
      const requestId = context.params.requestId;
      const data = snap.data() || {};
      const status = (data.status || "").toString();

      if (status !== "pending") {
        console.log("Skip: not pending", { requestId, status });
        return null;
      }

      const userId = (data.user_id || "").toString();
      const utr = String(data.utr || "")
        .trim()
        .toUpperCase();
      const planDays = Number(data.plan_days);
      const amount = Number(data.amount);
      const tier = String(data.tier || "");

      if (!userId || !utr || utr.length < 6) {
        await rejectRequest(requestId, "Missing user_id or invalid UTR");
        return null;
      }

      const plan = findPlan(planDays, amount, tier);
      if (!plan) {
        await rejectRequest(
          requestId,
          `No matching plan for days=${planDays} amount=${amount} tier=${tier}`,
        );
        return null;
      }

      const dup = await db.collection("payment_requests").where("utr", "==", utr).get();
      const duplicateApproved = dup.docs.some(
        (d) => d.id !== requestId && (d.data().status || "") === "approved",
      );
      if (duplicateApproved) {
        await rejectRequest(requestId, "Duplicate UTR already used");
        return null;
      }

      const userSnap = await db.collection("users").doc(userId).get();
      if (!userSnap.exists) {
        await rejectRequest(requestId, "User document not found");
        return null;
      }

      await snap.ref.update({
        status: "pending_verification",
        verified_plan_days: plan.days,
        verified_plan_price: plan.price,
        verified_plan_tier: plan.tier,
        submitted_at: admin.firestore.FieldValue.serverTimestamp(),
        note:
          "Payment submitted. Awaiting admin verification of UTR before premium activation.",
      });

      console.log("Payment request pending verification", {
        userId,
        requestId,
        utr,
        plan,
      });
      return null;
    });
}

module.exports = { createOnPaymentRequestCreatedTrigger };
