/**
 * Wraps Gen-1 HTTPS callables. App Check is opt-in via MVV_ENFORCE_APP_CHECK=true
 * (Flutter web skips App Check until ReCaptcha site key is configured).
 * @param {import('firebase-functions').region.RegionBuilder} fnAsia
 * @param {(data: any, context: import('firebase-functions').https.CallableContext) => Promise<any>} handler
 */
function secureHttpsOnCall(fnAsia, handler) {
  const enforceAppCheck = process.env.MVV_ENFORCE_APP_CHECK === "true";
  const runtimeOpts = enforceAppCheck ? { enforceAppCheck: true } : {};
  return fnAsia.runWith(runtimeOpts).https.onCall(handler);
}

module.exports = { secureHttpsOnCall };
