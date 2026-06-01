/// Inventory and conventions for Firestore **`users`** collection access (Phase 2 audit).
///
/// The app uses **`Collections.users`** in `contract.dart` as the **single literal** — new code must
/// not spell `'users'` again so renames remain possible.
///
/// ### Layers in use (overlap is intentional migration debt, not necessarily duplication)
///
/// **Identity / session:** `AuthController`, `AuthRepository`, `SessionManager`,
/// `session_query_auth_uid.dart`.
///
/// **Profile document (preferred for feature-facing reads/writes):** `ProfileRepository`,
/// `ProfileCompletionPolicy`, `AppInitializer`.
///
/// **Generic Result-shaped CRUD + identity helpers:** `FirestoreRepository`, `AppIdentity`;
/// high-volume callers include `InterestService`, `LikeService`.
///
/// **Heavy read/search/match:** `FirestoreService` (backend), `DiscoverService`, `FilterEngine`,
/// `RecommendationEngine`, `MatchEngine`.
///
/// **Admin & compliance:** `AdminService`, admin screens, `ProfileDocumentSubmissionService`.
///
/// **Analytics / presence / engagement:** `ProfileAnalyticsService`, `AnalyticsService` (feature),
/// `EngagementRepository`, `PresenceService`.
///
/// ### Screens (non-auth / non-chat focus for refactor planning)
///
/// **`privacy_settings_screen`** loads via **`ProfileRepository.getUserDocumentDataCacheFirst`**
/// (no direct `FirebaseFirestore` in that screen).
///
/// Typical pattern for the rest: **`FirebaseFirestore.instance`** on **`users`** or sibling collections — route new
/// work through **`ProfileRepository`**, **`AuthController.refreshUserData`**, **`FirestoreService`**,
/// or **`getDocumentCachedFirst`**. **`screens/auth/`** and **`screens/chat/`** are excluded from that
/// table until messaging/auth ownership is addressed.///
/// ### Legacy overlap
///
/// `legacy/compatibility.dart` (`FirebaseService`) mirrors “resolve by doc id / profile_id / auth_uid”
/// patterns also present in `FirestoreService` — consolidate only with coverage.
abstract final class FirestoreUsersAccessMap {
  FirestoreUsersAccessMap._();
}
