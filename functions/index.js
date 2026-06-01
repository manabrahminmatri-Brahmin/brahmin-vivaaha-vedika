/**
 * Thin entry point for Firebase deploy discovery (<10s init).
 * Heavy handlers live in all_functions.js and load on first access.
 */
"use strict";

const admin = require("firebase-admin");
if (!admin.apps.length) {
  admin.initializeApp();
}

const functions = require("firebase-functions");
const fnAsia = functions.region("asia-south1");
const db = admin.firestore();

const {
  createLookupIndianPincodeCallable,
} = require("./src/lookupIndianPincode");

exports.lookupIndianPincode = createLookupIndianPincodeCallable(fnAsia, { db });

/** @type {string[]} */
const DEFERRED_EXPORTS = [
  "getCloudinarySignature",
  "deleteCloudinaryPhoto",
  "createRazorpayOrder",
  "verifyRazorpayPayment",
  "razorpayWebhook",
  "updateLikesReceived",
  "sendBirthRequest",
  "sendCommunityRequest",
  "withdrawBirthRequest",
  "withdrawCommunityRequest",
  "transitionBirthRequestStatus",
  "transitionCommunityRequestStatus",
  "migrateInterestIdsToProfileDocIds",
  "migrateBirthAndCommunityRequestIdsToProfileDocIds",
  "setUserMpinSecure",
  "retryPremiumEntitlement",
  "transitionInterestStatus",
  "createOrResendInterest",
  "transitionPhotoRequest",
  "createChatRoom",
  "unlockContact",
  "validatePremiumAccess",
  "ensureSupportThread",
  "sendSupportMessage",
  "markSupportThreadRead",
  "createPhotoRequest",
  "recordProfileView",
  "recordLike",
  "setAdminCustomClaim",
  "onInAppNotificationCreatedPushFCM",
  "adminUpdateUserMembership",
  "adminApproveUserMembership",
  "adminSuspendUser",
  "adminRejectUser",
  "adminReactivateUser",
  "adminVerifyDocument",
  "adminDeleteUser",
  "completeMarriageFixed",
  "processScheduledProfileDeletions",
  "pruneStaleProfileViewsForMe",
  "pruneStaleEngagementForMe",
  "adminApprovePaymentRequest",
  "adminRejectPaymentRequest",
  "streamProfilePhoto",
];

let _deferred = null;
function loadDeferred() {
  if (!_deferred) {
    _deferred = require("./all_functions");
  }
  return _deferred;
}

for (const name of DEFERRED_EXPORTS) {
  Object.defineProperty(exports, name, {
    enumerable: true,
    configurable: true,
    get() {
      return loadDeferred()[name];
    },
  });
}
