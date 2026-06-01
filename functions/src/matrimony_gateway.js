/**
 * Secured matrimony actions — all high-risk writes go through these callables.
 * Clients initiate requests; server validates identity, blocks, premium, ownership.
 */
const functions = require("firebase-functions");
const { secureHttpsOnCall } = require("./callable_security");
const { MATRIMONY_LIMITS } = require("./rate_limit");
const {
  assertValidRequestDocId,
  normalizeAccessStatus,
  applyTransitionAudit,
  notifyRequesterOutcome,
} = require("./access_request_lifecycle");

/**
 * @param {{ db: FirebaseFirestore.Firestore, admin: typeof import('firebase-admin'), fnAsia: functions.region.RegionBuilder, deps: object }} ctx
 */
function registerMatrimonyCallables(ctx) {
  const { db, admin, fnAsia } = ctx;
  const resolveUserRefByAuthUid = ctx.deps.resolveUserRefByAuthUid;
  const resolveCallerProfileRef = ctx.deps.resolveCallerProfileRef;
  const resolveUserDocRefByAnyId = ctx.deps.resolveUserDocRefByAnyId;
  const logInterestTransition = ctx.deps.logInterestTransition;
  const rateLimiter = ctx.deps.rateLimiter;
  const isBlockedPair = ctx.deps.isBlockedPair;

  async function throttle(authUid, action) {
    const limits = MATRIMONY_LIMITS[action];
    if (rateLimiter && limits) {
      await rateLimiter.consume(authUid, action, limits);
    }
  }

  function parseDateLikeToMillis(value) {
    if (value == null) return null;
    if (typeof value === "string") {
      const ms = Date.parse(value);
      return Number.isFinite(ms) ? ms : null;
    }
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value?.toMillis === "function") {
      const ms = value.toMillis();
      return Number.isFinite(ms) ? ms : null;
    }
    if (value instanceof Date) {
      const ms = value.getTime();
      return Number.isFinite(ms) ? ms : null;
    }
    return null;
  }

  async function readPremiumEntitlement(userRef) {
    const snap = await userRef.get();
    if (!snap.exists) {
      return { active: false, reason: "user_not_found" };
    }
    const data = snap.data() || {};
    const membership =
      data.membership_json && typeof data.membership_json === "object"
        ? data.membership_json
        : {};
    const expiryMs = parseDateLikeToMillis(
      data.premium_expiry ||
        data.membership_expires_at ||
        data.membership_expiry_date ||
        membership.expiryDate ||
        membership.expiry_date ||
        membership.endDate
    );
    let tier = (
      data.membership_tier ||
        membership.tier ||
        membership.level ||
        data.subscription_tier ||
        ""
    )
      .toString()
      .toLowerCase()
      .trim();
    const paidTiers = new Set([
      "premium",
      "platinum",
      "gold",
      "silver",
    ]);
    if (
      (data.is_premium === true ||
        membership.isPremium === true ||
        membership.is_premium === true) &&
      !paidTiers.has(tier)
    ) {
      tier = "platinum";
    }
    const status = (data.membership_status || "").toString().toLowerCase();
    const flagged =
      data.is_premium === true ||
      membership.isPremium === true ||
      membership.is_premium === true ||
      paidTiers.has(tier) ||
      status === "premium" ||
      (status === "active" && paidTiers.has(tier));
    const hasValidExpiry = expiryMs != null && expiryMs > Date.now();
    const hasRootExpiryField =
      data.premium_expiry != null ||
      data.membership_expires_at != null ||
      data.membership_expiry_date != null;
    const active =
      (flagged && (expiryMs == null || expiryMs > Date.now())) ||
      (hasValidExpiry && hasRootExpiryField);
    return {
      active,
      expiryMs,
      tier,
      reason: active ? "active" : "not_premium",
    };
  }

  async function assertOwnsProfileDocId(callerRef, profileDocId) {
    if (!callerRef) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Could not resolve your profile."
      );
    }
    const expected = (profileDocId || "").toString().trim();
    if (!expected || callerRef.id !== expected) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "You can only act on your own profile."
      );
    }
    return callerRef;
  }

  async function writeSecurityAudit(event, fields) {
    try {
      await db.collection("security_audit_logs").add({
        event,
        module: "matrimony_gateway",
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        ...fields,
      });
    } catch (e) {
      console.warn("security_audit_logs write failed:", e?.message || e);
    }
  }

  async function fetchProfileSnapshot(userDocId) {
    const snap = await db.collection("users").doc(userDocId).get();
    if (!snap.exists) return {};
    const u = snap.data() || {};
    const profile =
      u.profile && typeof u.profile === "object" ? u.profile : {};
    return {
      from_first_name: (u.first_name || profile.first_name || "").toString(),
      from_last_name: (u.last_name || profile.last_name || "").toString(),
      from_profile_id: (u.profile_id || "").toString(),
      from_photo_url: (u.photo_url || profile.photo_url || "").toString(),
      from_city: (u.city || profile.city || "").toString(),
      from_state: (u.state || profile.state || "").toString(),
    };
  }

  const transitionInterestStatus = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be logged in to update interest status."
      );
    }
    await throttle(context.auth.uid, "transitionInterestStatus");

    const interestId = (data?.interestId || "").toString().trim();
    const action = (data?.action || "").toString().trim().toLowerCase();
    const requestedStatus = (data?.status || "").toString().trim().toLowerCase();
    const declineReason = (data?.declineReason || data?.rejectionReason || "")
      .toString()
      .trim();
    const responseMessage = (data?.responseMessage || data?.message || "")
      .toString()
      .trim();

    if (!interestId || !action) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "interestId and action are required."
      );
    }

    if (!["accept", "reject", "withdraw"].includes(action)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Unsupported interest action."
      );
    }

    const callerRef = await resolveCallerProfileRef(
      context,
      (data?.requesterId || data?.fromUserId || "").toString().trim()
    );
    const callerProfileId = callerRef ? callerRef.id : "";

    const interestRef = db.collection("interests").doc(interestId);
    const interestSnap = await interestRef.get();

    if (!interestSnap.exists && action === "withdraw") {
      await logInterestTransition({
        interestId,
        action,
        actorUid: context.auth.uid,
        result: "noop_not_found",
      });
      return {
        success: true,
        action,
        status: "withdrawn",
        interestId,
        duplicateIgnored: true,
      };
    }
    if (!interestSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Interest not found.");
    }

    const interest = interestSnap.data() || {};
    const fromUserId = (interest.from_user_id || "").toString();
    const toUserId = (interest.to_user_id || "").toString();
    const currentStatus = (interest.status || "pending").toString().toLowerCase();

    if (await isBlockedPair(fromUserId, toUserId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Action blocked due to member block."
      );
    }

    if (action === "withdraw") {
      await assertOwnsProfileDocId(callerRef, fromUserId);
      if (currentStatus !== "pending" && currentStatus !== "accepted") {
        await logInterestTransition({
          interestId,
          action,
          actorUid: context.auth.uid,
          result: "noop_already_processed",
          fromStatus: currentStatus,
        });
        return {
          success: true,
          action,
          status: currentStatus,
          interestId,
          duplicateIgnored: true,
        };
      }

      const nowServer = admin.firestore.FieldValue.serverTimestamp();
      if (currentStatus === "pending") {
        await interestRef.delete();
      } else {
        await interestRef.set(
          {
            status: "withdrawn",
            withdrawn_at: nowServer,
            updated_at: nowServer,
          },
          { merge: true }
        );
      }
      await logInterestTransition({
        interestId,
        action,
        actorUid: context.auth.uid,
        result: "applied",
        fromStatus: currentStatus,
        toStatus: "withdrawn",
      });
      await writeSecurityAudit("interest_withdrawn", {
        actor_user_id: callerProfileId,
        actor_auth_uid: context.auth.uid,
        document_id: interestId,
        target_user_id: toUserId,
        from_status: currentStatus,
      });
      return { success: true, action, status: "withdrawn", interestId };
    }

    await assertOwnsProfileDocId(callerRef, toUserId);

    if (currentStatus !== "pending") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Only pending interests can be updated."
      );
    }

    const finalStatus =
      action === "accept"
        ? "accepted"
        : requestedStatus === "declined"
          ? "declined"
          : "rejected";

    if (currentStatus === finalStatus) {
      await logInterestTransition({
        interestId,
        action,
        actorUid: context.auth.uid,
        result: "noop_duplicate_transition",
        fromStatus: currentStatus,
        toStatus: finalStatus,
      });
      return {
        success: true,
        action,
        status: finalStatus,
        interestId,
        duplicateIgnored: true,
      };
    }

    const updateData = {
      status: finalStatus,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      responded_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (action === "reject" && declineReason) {
      updateData.decline_reason = declineReason;
      updateData.rejectionReason = declineReason;
    }
    if (action === "accept" && responseMessage) {
      updateData.response_message = responseMessage;
      updateData.responseMessage = responseMessage;
    }

    await interestRef.set(updateData, { merge: true });
    await logInterestTransition({
      interestId,
      action,
      actorUid: context.auth.uid,
      result: "applied",
      fromStatus: currentStatus,
      toStatus: finalStatus,
    });
    await writeSecurityAudit(
      action === "accept" ? "interest_accepted" : "interest_rejected",
      {
        actor_user_id: callerProfileId,
        actor_auth_uid: context.auth.uid,
        document_id: interestId,
        target_user_id: fromUserId,
        from_status: currentStatus,
        to_status: finalStatus,
      }
    );

    return { success: true, action, status: finalStatus, interestId };
  });

  const createOrResendInterest = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "createOrResendInterest");

    const fromUserId = (data?.fromUserId || data?.from_user_id || "").toString().trim();
    const toUserId = (data?.toUserId || data?.to_user_id || "").toString().trim();
    const message = (data?.message || "").toString().trim();
    const forceResend = data?.forceResend === true || data?.force_resend === true;

    if (!fromUserId || !toUserId || fromUserId === toUserId) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid interest users.");
    }

    const callerRef = await resolveCallerProfileRef(context, fromUserId);
    await assertOwnsProfileDocId(callerRef, fromUserId);

    if (await isBlockedPair(fromUserId, toUserId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "You cannot send interest to a blocked member."
      );
    }

    const callerUid = context.auth.uid;
    const interestId = `${fromUserId}_${toUserId}`;
    const interestRef = db.collection("interests").doc(interestId);
    const existingSnap = await interestRef.get();

    if (existingSnap.exists) {
      const existingStatus = (existingSnap.data()?.status || "pending")
        .toString()
        .toLowerCase();
      if (existingStatus === "pending" && !forceResend) {
        return {
          success: true,
          interestId,
          status: "pending",
          duplicateIgnored: true,
        };
      }
      if (existingStatus === "accepted") {
        throw new functions.https.HttpsError(
          "already-exists",
          "You are already connected."
        );
      }
    }

    const [senderSnap, receiverSnap] = await Promise.all([
      db.collection("users").doc(fromUserId).get(),
      db.collection("users").doc(toUserId).get(),
    ]);
    if (!receiverSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Target user not found.");
    }

    const sender = senderSnap.data() || {};
    const receiver = receiverSnap.data() || {};
    const senderProfile =
      sender.profile && typeof sender.profile === "object" ? sender.profile : {};
    const receiverProfile =
      receiver.profile && typeof receiver.profile === "object"
        ? receiver.profile
        : {};

    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
      from_user_id: fromUserId,
      to_user_id: toUserId,
      from_auth_uid: callerUid,
      to_auth_uid: (receiver.auth_uid || "").toString().trim(),
      from_profile_id: (sender.profile_id || data?.fromProfileId || "").toString(),
      to_profile_id: (receiver.profile_id || data?.toProfileId || "").toString(),
      from_first_name: (sender.first_name || senderProfile.first_name || "").toString(),
      from_last_name: (sender.last_name || senderProfile.last_name || "").toString(),
      to_first_name: (receiver.first_name || receiverProfile.first_name || "").toString(),
      to_last_name: (receiver.last_name || receiverProfile.last_name || "").toString(),
      status: "pending",
      message,
      created_at: existingSnap.exists
        ? existingSnap.data()?.created_at || now
        : now,
      updated_at: now,
    };

    await interestRef.set(payload, { merge: true });

    await db
      .collection("users")
      .doc(fromUserId)
      .set(
        { interests_sent: admin.firestore.FieldValue.increment(1), updated_at: now },
        { merge: true }
      )
      .catch(() => {});
    await db
      .collection("users")
      .doc(toUserId)
      .set(
        {
          interests_received: admin.firestore.FieldValue.increment(1),
          updated_at: now,
        },
        { merge: true }
      )
      .catch(() => {});

    const senderFirst = payload.from_first_name || "Someone";
    const senderLast = payload.from_last_name || "";
    const senderLabel = `${senderFirst}${senderLast ? ` ${senderLast}` : ""}`.trim();

    if (!existingSnap.exists || forceResend) {
      const nowIso = new Date().toISOString();
      try {
        await db.collection("notifications").add({
          user_id: toUserId,
          to_user: toUserId,
          from_user: fromUserId,
          type: "interest_received",
          title: "New Interest Received!",
          body: `${senderLabel} is interested in your profile`,
          message: `${senderLabel} is interested in your profile`,
          related_user_id: fromUserId,
          related_profile_id: payload.from_profile_id,
          interest_id: interestId,
          is_read: false,
          created_at: nowIso,
        });
      } catch (e) {
        console.warn("createOrResendInterest notification failed:", e?.message || e);
      }
    }

    await logInterestTransition({
      interestId,
      action: forceResend ? "resend" : "send",
      actorUid: callerUid,
      result: "applied",
      fromStatus: existingSnap.exists
        ? (existingSnap.data()?.status || "").toString().toLowerCase()
        : "",
      toStatus: "pending",
    });
    await writeSecurityAudit("interest_sent", {
      actor_user_id: fromUserId,
      actor_auth_uid: callerUid,
      document_id: interestId,
      target_user_id: toUserId,
    });

    return {
      success: true,
      interestId,
      status: "pending",
      receiverDocId: toUserId,
      resent: forceResend,
    };
  });

  const transitionPhotoRequest = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "transitionPhotoRequest");

    const rawActionForThrottle = (data?.action || data?.status || "")
      .toString()
      .trim()
      .toLowerCase();
    if (rawActionForThrottle === "revoke" || rawActionForThrottle === "stop") {
      await throttle(context.auth.uid, "privacyRevokeAccess");
    }

    const requestId = assertValidRequestDocId(
      data?.requestId || data?.request_id || ""
    );
    const action = (data?.action || data?.status || "").toString().trim().toLowerCase();

    if (!action) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "action is required."
      );
    }

    const approve =
      action === "approve" ||
      action === "approved" ||
      action === "accept" ||
      action === "accepted" ||
      action === "grant" ||
      action === "granted";
    const reject =
      action === "reject" ||
      action === "decline" ||
      action === "rejected" ||
      action === "declined" ||
      action === "deny" ||
      action === "denied";
    const withdraw = action === "withdraw" || action === "withdrawn";
    const remind =
      action === "remind" ||
      action === "reminder" ||
      action === "resend";
    const revoke =
      action === "revoke" ||
      action === "revoked" ||
      action === "withdraw_access";
    const stop = action === "stop" || action === "stopped";

    if (!approve && !reject && !withdraw && !remind && !revoke && !stop) {
      throw new functions.https.HttpsError("invalid-argument", "Unsupported photo action.");
    }

    const callerRef = await resolveCallerProfileRef(context, "");
    const ref = db.collection("photo_requests").doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Photo request not found.");
    }

    const row = snap.data() || {};
    const fromUserId = (row.from_user_id || row.fromUserId || "").toString().trim();
    const toUserId = (row.to_user_id || row.toUserId || "").toString().trim();
    const expectedRequestId = `${fromUserId}_${toUserId}`;
    if (!fromUserId || !toUserId || requestId !== expectedRequestId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Photo request document binding mismatch."
      );
    }
    const current = normalizeAccessStatus(row.status);

    if (withdraw || remind) {
      await assertOwnsProfileDocId(callerRef, fromUserId);
      if (current !== "pending") {
        return {
          success: true,
          requestId,
          status: current,
          duplicateIgnored: true,
        };
      }
      if (await isBlockedPair(fromUserId, toUserId)) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Action blocked due to member block."
        );
      }
      if (withdraw) {
        await ref.set(
          {
            status: "withdrawn",
            withdrawn_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        await writeSecurityAudit("photo_request_withdrawn", {
          actor_user_id: callerRef.id,
          actor_auth_uid: context.auth.uid,
          document_id: requestId,
          target_user_id: toUserId,
          to_status: "withdrawn",
        });
        return { success: true, requestId, status: "withdrawn" };
      }
      await ref.set(
        {
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          reminder_at: admin.firestore.FieldValue.serverTimestamp(),
          reminder_count: admin.firestore.FieldValue.increment(1),
        },
        { merge: true }
      );
      await writeSecurityAudit("photo_request_reminder", {
        actor_user_id: callerRef.id,
        actor_auth_uid: context.auth.uid,
        document_id: requestId,
        target_user_id: toUserId,
      });
      return { success: true, requestId, status: "pending" };
    }

    await assertOwnsProfileDocId(callerRef, toUserId);

    const nowServer = admin.firestore.FieldValue.serverTimestamp();
    const hasExistingGrantedAt =
      Boolean(row.grantedAt) ||
      Boolean(row.granted_at);

    if (revoke) {
      if (current !== "granted") {
        return {
          success: true,
          requestId,
          status: current,
          duplicateIgnored: true,
        };
      }

      const payload = applyTransitionAudit(
        {
          revokedAt: nowServer,
          revoked_at: nowServer,
          updatedAt: nowServer,
          updated_at: nowServer,
        },
        {
          fromStatus: current,
          toStatus: "revoked",
          actorUid: context.auth.uid,
          actorRole: "owner",
          row,
        }
      );
      if (!hasExistingGrantedAt) {
        payload.grantedAt = nowServer;
        payload.granted_at = nowServer;
      }

      await ref.set(payload, { merge: true });

      await writeSecurityAudit("photo_access_revoked", {
        actor_user_id: callerRef.id,
        actor_auth_uid: context.auth.uid,
        document_id: requestId,
        target_user_id: fromUserId,
        to_status: "revoked",
      });

      const ownerName =
        (row.to_first_name || row.owner_name || "Profile Owner").toString();
      await notifyRequesterOutcome(db, {
        kind: "photo",
        outcome: "revoked",
        requesterId: fromUserId,
        ownerId: toUserId,
        ownerName,
        requestDocId: requestId,
        requesterProfileId: (row.from_profile_id || row.requester_profile_id || "")
          .toString(),
      });

      return { success: true, requestId, status: "revoked" };
    }

    if (stop) {
      if (current !== "granted") {
        return {
          success: true,
          requestId,
          status: current,
          duplicateIgnored: true,
        };
      }

      const payload = applyTransitionAudit(
        {
          stoppedAt: nowServer,
          stopped_at: nowServer,
          updatedAt: nowServer,
          updated_at: nowServer,
        },
        {
          fromStatus: current,
          toStatus: "stopped",
          actorUid: context.auth.uid,
          actorRole: "owner",
          row,
        }
      );
      if (!hasExistingGrantedAt) {
        payload.grantedAt = nowServer;
        payload.granted_at = nowServer;
      }

      await ref.set(payload, { merge: true });

      await writeSecurityAudit("photo_access_stopped", {
        actor_user_id: callerRef.id,
        actor_auth_uid: context.auth.uid,
        document_id: requestId,
        target_user_id: fromUserId,
        to_status: "stopped",
      });

      const ownerName =
        (row.to_first_name || row.owner_name || "Profile Owner").toString();
      await notifyRequesterOutcome(db, {
        kind: "photo",
        outcome: "stopped",
        requesterId: fromUserId,
        ownerId: toUserId,
        ownerName,
        requestDocId: requestId,
        requesterProfileId: (row.from_profile_id || row.requester_profile_id || "")
          .toString(),
      });

      return { success: true, requestId, status: "stopped" };
    }

    // For accept/deny we keep deny/decline strict for the pending state.
    if (reject) {
      if (current !== "pending") {
        return {
          success: true,
          requestId,
          status: current,
          duplicateIgnored: true,
        };
      }
    }

    if (approve) {
      // Allow grant even if current is revoked (Grant Again),
      // and allow legacy accepted/previous granted values.
      const allow = [
        "pending",
        "revoked",
        "stopped",
        "denied",
        "granted",
        "accepted",
      ];
      if (!allow.includes(current)) {
        return {
          success: true,
          requestId,
          status: current,
          duplicateIgnored: true,
        };
      }
    }

    if (approve || reject) {
      if (await isBlockedPair(fromUserId, toUserId)) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Action blocked due to member block."
        );
      }
    }

    if (approve) {
      const payload = applyTransitionAudit(
        {
          responded_at: nowServer,
          updated_at: nowServer,
          updatedAt: nowServer,
        },
        {
          fromStatus: current,
          toStatus: "granted",
          actorUid: context.auth.uid,
          actorRole: "owner",
          row,
        }
      );
      if (!hasExistingGrantedAt) {
        payload.grantedAt = nowServer;
        payload.granted_at = nowServer;
      }
      await ref.set(payload, { merge: true });

      await writeSecurityAudit("photo_access_granted", {
        actor_user_id: callerRef.id,
        actor_auth_uid: context.auth.uid,
        document_id: requestId,
        target_user_id: fromUserId,
        to_status: "granted",
      });

      const ownerName =
        (row.to_first_name || row.owner_name || "Profile Owner").toString();
      await notifyRequesterOutcome(db, {
        kind: "photo",
        outcome: "granted",
        requesterId: fromUserId,
        ownerId: toUserId,
        ownerName,
        requestDocId: requestId,
        requesterProfileId: (row.from_profile_id || row.requester_profile_id || "")
          .toString(),
      });

      return { success: true, requestId, status: "granted" };
    }

    if (reject) {
      const payload = applyTransitionAudit(
        {
          responded_at: nowServer,
          updated_at: nowServer,
          updatedAt: nowServer,
          deniedAt: nowServer,
          denied_at: nowServer,
        },
        {
          fromStatus: current,
          toStatus: "denied",
          actorUid: context.auth.uid,
          actorRole: "owner",
          row,
        }
      );
      await ref.set(payload, { merge: true });

      await writeSecurityAudit("photo_access_denied", {
        actor_user_id: callerRef.id,
        actor_auth_uid: context.auth.uid,
        document_id: requestId,
        target_user_id: fromUserId,
        to_status: "denied",
      });

      const ownerName =
        (row.to_first_name || row.owner_name || "Profile Owner").toString();
      await notifyRequesterOutcome(db, {
        kind: "photo",
        outcome: "denied",
        requesterId: fromUserId,
        ownerId: toUserId,
        ownerName,
        requestDocId: requestId,
        requesterProfileId: (row.from_profile_id || row.requester_profile_id || "")
          .toString(),
      });

      return { success: true, requestId, status: "denied" };
    }

    return { success: true, requestId, status: current, duplicateIgnored: true };
  });

  const createChatRoom = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "createChatRoom");

    const otherUserHint = (data?.otherUserId || data?.peerUserId || "")
      .toString()
      .trim();
    if (!otherUserHint) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "otherUserId is required."
      );
    }

    const callerRef = await resolveCallerProfileRef(
      context,
      (data?.requesterId || "").toString().trim()
    );
    if (!callerRef) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Caller profile mapping not found."
      );
    }
    const me = callerRef.id;

    let otherUserId = otherUserHint;
    let otherAuthUid = "";
    if (resolveUserDocRefByAnyId) {
      const otherRef = await resolveUserDocRefByAnyId(otherUserHint);
      if (!otherRef) {
        throw new functions.https.HttpsError("not-found", "Chat partner not found.");
      }
      otherUserId = otherRef.id;
      const otherSnap = await otherRef.get();
      otherAuthUid = (otherSnap.data()?.auth_uid || "").toString().trim();
    }

    if (me === otherUserId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Cannot create chat with yourself."
      );
    }

    if (await isBlockedPair(me, otherUserId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Chat is not available due to block."
      );
    }

    const interestIdA = `${me}_${otherUserId}`;
    const interestIdB = `${otherUserId}_${me}`;
    const [ia, ib] = await Promise.all([
      db.collection("interests").doc(interestIdA).get(),
      db.collection("interests").doc(interestIdB).get(),
    ]);
    const accepted =
      (ia.exists && (ia.data()?.status || "").toString().toLowerCase() === "accepted") ||
      (ib.exists && (ib.data()?.status || "").toString().toLowerCase() === "accepted");
    if (!accepted) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Chat is available after interest is accepted."
      );
    }

    const sorted = [me, otherUserId].sort();
    const chatId = `${sorted[0]}_${sorted[1]}`;
    const chatRef = db.collection("chats").doc(chatId);
    const chatSnap = await chatRef.get();
    const now = admin.firestore.FieldValue.serverTimestamp();

    const participantAuthUids = [context.auth.uid];
    if (otherAuthUid && !participantAuthUids.includes(otherAuthUid)) {
      participantAuthUids.push(otherAuthUid);
    }

    const chatPayload = {
      participants: sorted,
      participant_auth_uids: participantAuthUids,
      deleted_for: admin.firestore.FieldValue.arrayRemove(me),
      updated_at: now,
    };

    if (!chatSnap.exists) {
      await chatRef.set({
        ...chatPayload,
        intro_message_sent_by: [],
        created_at: now,
        lastMessage: "",
      });
    } else {
      await chatRef.set(chatPayload, { merge: true });
    }

    await writeSecurityAudit("chat_room_created", {
      actor_user_id: me,
      actor_auth_uid: context.auth.uid,
      document_id: chatId,
      target_user_id: otherUserId,
    });

    return { success: true, chatId };
  });

  const unlockContact = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "unlockContact");

    const interestId = (data?.interestId || "").toString().trim();
    const peerUserId = (data?.peerUserId || data?.targetUserId || "")
      .toString()
      .trim();

    if (!interestId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "interestId is required."
      );
    }

    const callerRef = await resolveCallerProfileRef(context, "");
    const premium = await readPremiumEntitlement(callerRef);
    if (!premium.active) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Premium membership is required to view contact details."
      );
    }

    const interestSnap = await db.collection("interests").doc(interestId).get();
    if (!interestSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Interest not found.");
    }

    const interest = interestSnap.data() || {};
    const fromId = (interest.from_user_id || "").toString();
    const toId = (interest.to_user_id || "").toString();
    const status = (interest.status || "").toString().toLowerCase();

    if (status !== "accepted") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Contact unlock requires accepted interest."
      );
    }

    const callerId = callerRef.id;
    if (callerId !== fromId && callerId !== toId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "You are not a participant on this interest."
      );
    }

    const peer = peerUserId || (callerId === fromId ? toId : fromId);
    if (await isBlockedPair(callerId, peer)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Contact unavailable due to block."
      );
    }

    await writeSecurityAudit("contact_unlocked", {
      actor_user_id: callerId,
      actor_auth_uid: context.auth.uid,
      document_id: interestId,
      target_user_id: peer,
    });

    return { success: true, interestId, peerUserId: peer, entitled: true };
  });

  async function isElevatedAdminUser(context) {
    if (!context.auth) return false;
    const token = context.auth.token || {};
    if (token.admin === true || token.is_admin === true) {
      return true;
    }
    try {
      const ref = await resolveUserRefByAuthUid(context.auth.uid);
      if (ref && ref.exists && ref.data()?.is_admin === true) {
        return true;
      }
      const sessionSnap = await db
        .collection("admin_sessions")
        .doc(context.auth.uid)
        .get();
      return sessionSnap.exists && sessionSnap.data()?.is_admin === true;
    } catch (e) {
      console.warn("isElevatedAdminUser:", e?.message || e);
      return false;
    }
  }

  const ensureSupportThread = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "ensureSupportThread");

    const callerRef = await resolveCallerProfileRef(
      context,
      (data?.requesterId || "").toString().trim()
    );
    const threadId = callerRef.id;
    const profile = await fetchProfileSnapshot(threadId);
    const displayName = [profile.first_name, profile.last_name]
      .filter(Boolean)
      .join(" ")
      .trim();
    const threadRef = db.collection("support_threads").doc(threadId);
    const threadSnap = await threadRef.get();
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (!threadSnap.exists) {
      await threadRef.set({
        user_id: threadId,
        user_auth_uid: context.auth.uid,
        user_display_name: displayName || "Member",
        user_mobile: (profile.mobile_number || "").toString(),
        user_profile_id: (profile.profile_id || "").toString(),
        status: "open",
        last_message: "",
        unread_admin: 0,
        unread_user: 0,
        created_at: now,
        updated_at: now,
      });
      await threadRef.collection("messages").add({
        sender_role: "admin",
        sender_id: "support",
        sender_label: "mana Vivaaha Vedika Support",
        body:
          "Namaste! Welcome to mana Vivaaha Vedika support. Share your profile ID and question — our team will reply here.",
        created_at: now,
        read_by_user: false,
        read_by_admin: true,
      });
      await threadRef.set({
        last_message:
          "Namaste! Welcome to mana Vivaaha Vedika support. Share your profile ID and question — our team will reply here.",
        unread_user: 1,
        updated_at: now,
      });
      await writeSecurityAudit("support_thread_created", {
        actor_user_id: threadId,
        actor_auth_uid: context.auth.uid,
        document_id: threadId,
      });
    }

    return { success: true, threadId };
  });

  const sendSupportMessage = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "sendSupportMessage");

    const body = (data?.body || "").toString().trim();
    if (!body || body.length > 2000) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Message must be between 1 and 2000 characters."
      );
    }

    const adminMode = await isElevatedAdminUser(context);
    let threadId = (data?.threadId || "").toString().trim();
    let senderRole = "user";
    let senderId = "";
    let senderLabel = "";

    if (adminMode) {
      if (!threadId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "threadId is required for admin replies."
        );
      }
      senderRole = "admin";
      senderId = context.auth.uid;
      senderLabel = "Support Team";
    } else {
      const callerRef = await resolveCallerProfileRef(
        context,
        (data?.requesterId || "").toString().trim()
      );
      threadId = callerRef.id;
      senderRole = "user";
      senderId = callerRef.id;
      const profile = await fetchProfileSnapshot(threadId);
      senderLabel = [profile.first_name, profile.last_name]
        .filter(Boolean)
        .join(" ")
        .trim() || "Member";
    }

    const threadRef = db.collection("support_threads").doc(threadId);
    const threadSnap = await threadRef.get();
    if (!threadSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Support thread not found."
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const preview =
      body.length > 120 ? `${body.slice(0, 117)}...` : body;

    await threadRef.collection("messages").add({
      sender_role: senderRole,
      sender_id: senderId,
      sender_label: senderLabel,
      body,
      created_at: now,
      read_by_user: senderRole === "user",
      read_by_admin: senderRole === "admin",
    });

    const threadUpdate = {
      last_message: preview,
      updated_at: now,
      status: "open",
    };
    if (senderRole === "user") {
      threadUpdate.unread_admin = admin.firestore.FieldValue.increment(1);
    } else {
      threadUpdate.unread_user = admin.firestore.FieldValue.increment(1);
    }
    await threadRef.set(threadUpdate, { merge: true });

    await writeSecurityAudit("support_message_sent", {
      actor_user_id: senderId || threadId,
      actor_auth_uid: context.auth.uid,
      document_id: threadId,
      sender_role: senderRole,
    });

    return { success: true, threadId };
  });

  const markSupportThreadRead = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "markSupportThreadRead");

    const adminMode = await isElevatedAdminUser(context);
    let threadId = (data?.threadId || "").toString().trim();

    if (!adminMode) {
      const callerRef = await resolveCallerProfileRef(
        context,
        (data?.requesterId || "").toString().trim()
      );
      threadId = callerRef.id;
    }

    if (!threadId) {
      throw new functions.https.HttpsError("invalid-argument", "threadId is required.");
    }

    const threadRef = db.collection("support_threads").doc(threadId);
    const patch = {
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (adminMode) {
      patch.unread_admin = 0;
    } else {
      patch.unread_user = 0;
    }
    await threadRef.set(patch, { merge: true });

    return { success: true, threadId };
  });

  const validatePremiumAccess = secureHttpsOnCall(fnAsia, async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    await throttle(context.auth.uid, "validatePremiumAccess");

    const feature = (data?.feature || "").toString().trim();
    const callerRef = await resolveCallerProfileRef(
      context,
      (data?.userDocId || "").toString().trim()
    );
    if (!callerRef) {
      return { success: true, entitled: false, reason: "profile_not_found", feature };
    }

    const premium = await readPremiumEntitlement(callerRef);
    return {
      success: true,
      entitled: premium.active,
      reason: premium.reason,
      feature,
      tier: premium.tier || "",
      expiryMs: premium.expiryMs,
      userDocId: callerRef.id,
    };
  });

  return {
    transitionInterestStatus,
    createOrResendInterest,
    transitionPhotoRequest,
    createChatRoom,
    unlockContact,
    validatePremiumAccess,
    ensureSupportThread,
    sendSupportMessage,
    markSupportThreadRead,
  };
}

module.exports = { registerMatrimonyCallables };
