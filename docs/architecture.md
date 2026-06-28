# Read the World Architecture

## Surfaces

- Flutter app (`apps/app`) owns the logged-in product across iOS, Android, and web.
  When Firebase is configured, route changes are observed by Firebase Analytics
  and the controller logs the core product events: answer selection, prediction
  submit/lock, reveal views, archive practice answers, result sharing, friend
  invites/acceptance, notification opt-in/out, and auth login/sign-up.
- Next.js (`apps/web`) owns the public marketing site and the protected admin surface.
  The same App Hosting backend can serve `readtheworld.today` and `admin.readtheworld.today`; Next Proxy rewrites requests for `admin.readtheworld.today` to `/admin`.
  The marketing app owns first-party SEO metadata, canonical links, `/robots.txt`, and `/sitemap.xml`; the admin route is explicitly marked `noindex,nofollow`.
- Firebase Functions (`functions`) owns official answer submission, daily close/open, scoring, admin mutations, and `rtw.codes` link resolution.
- Scheduled Functions send both core daily notifications: a result-ready prompt shortly after midnight Eastern and a daily-question prompt in the morning Eastern. Notification sends exclude users who have explicitly turned off the account reminder toggle.
  The Flutter reminder toggle also disables the current FCM token when a user opts out; the profile-level `dailyReminder: false` remains the server-side backstop for any stale tokens.
  Flutter web ships `firebase-messaging-sw.js` for background messages and loads Firebase app config through Firebase Hosting's reserved `/__/firebase/init.js` endpoint; `npm run app:build:web` copies that worker into the `apps/app/build/web` deploy artifact after Flutter builds.
- Firebase Functions also owns public marketing waitlist capture through `joinWaitlist`, so unauthenticated visitors do not need direct Firestore write access.
- Admin dashboard reads use the admin-claim-protected `getAdminOverview` callable, which returns bounded aggregate counts, recent questions/results, live answer counters, category activity, and aggregate audience slices without exposing raw user rows.
- Admin reads recent waitlist signups through the admin-claim-protected `listWaitlist` callable and exports CSV client-side.
- Admin question writes run through `upsertQuestion`, which validates status, option IDs, daily keys, and chronological publish/close windows before saving.
- Admin notification broadcasts run through `sendBroadcastNotification`; the callable validates copy and relative app routes, targets enabled FCM tokens by audience, disables invalid tokens, and writes a `notificationCampaigns` audit row.
- Admin feature-flag changes run through Remote Config via `getAdminAppConfig` and `setAdminFeatureFlag`; Flutter consumes the same flags for party mode, friends/social, friends leaderboard, result sharing, and onboarding demographics while keeping defaults enabled. Functions also enforce the social/share flags on invite creation/acceptance, friend mutations, result-share creation, and short-link resolution so direct callable or browser-link access cannot bypass disabled features.
- Archive/history replay, peek/reveal practice, and party answer mode save only non-official practice answers through `savePracticeAnswer`; these records never increment official counters, Read Score, streaks, category stats, or leaderboards.
- Friend rows hydrate from `users/{uid}/friends`; answer-visibility toggles and friend removal run through callables so reciprocal friendship state stays consistent and direct client writes remain blocked.
- Short-link and invite metadata are server-owned. Clients request share/invite links through callables; Firestore rules block direct client writes to `links` and `invites`.
  Invite links expire after 90 days; result links expire after 30 days and can only be created or resolved when the target result exists and `questions/{questionId}.status == "closed"`.
  App-created share URLs point to `readtheworld.today/share/{code}` so crawlers receive server-rendered Open Graph metadata and a generated question image; that page sends people back through `rtw.codes/{code}` so the existing app-link resolver and counters still run.
  The `rtw.codes` resolver increments open counters only for valid, unexpired, currently revealable links.
  Installed-app Universal/App Links that open directly to `rtw.codes/{code}` are handled by the Flutter `/:code` route, which calls `resolveShortCode` and forwards to the invite or reveal surface.
- Account data clearing runs through `clearMyData`, which resets scoring state, removes private answer/history/category/friend data, removes reciprocal friend rows, adjusts unscored live counters, and clears server-owned short-link/invite metadata tied to the user.
  Firestore rules block direct client user-document deletes so clients cannot bypass that cleanup path and leave stale counters, friend rows, links, or leaderboard data behind.
- Firebase project: `read-the-world-74f2a` (`863014025103`) under the `readtheworld.today` parent org.
- Firebase setup currently includes linked billing, Firestore Native mode in `nam5`, deployed Firestore rules/indexes, deployed Remote Config defaults, enabled anonymous/email/password/Google Auth providers, Firebase web/iOS/Android app registrations, Hosting sites for Flutter web/short links/redirects, and an App Hosting backend named `read-the-world-web` in `us-central1`.
- Firestore composite indexes are checked into `firebase/firestore.indexes.json` for the active runtime queries, including collection-group answer aggregation, scheduled-question opening, and live-question closing. Notification-token sends use Firestore single-field collection-group indexing, so no redundant composite index is committed. The readiness script validates the required composite indexes before deploy.

## Daily lifecycle

1. Admin creates a draft question and schedules `publishAt` / `closeAt`.
2. The scheduled function closes due live questions, then opens the next scheduled
   question at midnight Eastern only if no live question remains. This keeps the
   client live-question query unambiguous and avoids multiple official dailies.
3. Clients call `submitPrediction`; direct answer writes are denied by Firestore rules.
4. At close, Functions aggregates hidden counters, writes `dailyResults`, computes Read Accuracy, percentile, Read Score delta, streaks, and category stats.
   Signed prediction bias (`predictedShare - actualShare`) is also stored on answer/history records and rolled up on user/category stats for over/under-estimation insights.
5. Closed results become readable by clients after `questions/{questionId}.status == "closed"`; Functions callables use the same closed-question gate before saving replay answers or issuing/resolving result links. Admin recomputes preserve the original question/result `closedAt` timestamps so history and admin ordering do not jump when old scores are recalculated.

## Credentials still required

- Web/iOS/Android Firebase app configs for project `read-the-world-74f2a`.
- Firebase Auth provider setup for Google, Apple, and email/password, including web/iOS Google OAuth client IDs and the iOS reversed client ID URL scheme.
- Hosting target IDs for `app`, `links`, and `redirect`.
- Firebase App Hosting backend for `readtheworld.today` / `admin.readtheworld.today`.
- Apple team ID, iOS bundle ID, Android package name, and SHA-256 fingerprints for `rtw.codes` app links.
