# Deploy checklist

Practical steps to ship the current `main`. Split by surface — backend/web are
close to one-command; iOS/Android stores are a real release process.

## 0. Preflight
- [ ] `git pull` on `main` (this session pushed 25 commits up to `e38d59a`).
- [ ] Functions build + tests green:
  ```
  cd functions && npm ci && npx tsc --noEmit && npm test
  ```
- [ ] App analyzes + tests green:
  ```
  cd apps/app && flutter analyze && flutter test
  ```
- [ ] Readiness scripts (repo already ships these):
  ```
  node scripts/check-deployment-readiness.mjs
  node scripts/check-native-readiness.mjs
  ```

## 1. Cloud Functions  (changed a lot this session)
World lifecycle + scoring, `getWorldLeaderboard`, `notifyMembersOfJoin`, and the
`lockRoomAnswers` changes all live here.
```
cd functions && npm run build
firebase deploy --only functions
```
- [ ] Watch logs for the first `rolloverRooms` / lock after deploy.

## 2. Firestore rules / indexes
- **No rules changes this session** — existing rules already cover the new World
  paths (day reads for members/world, own-answer owner reads, writes are
  admin-SDK). Deploy only if `firebase/firestore.rules` actually changed:
  ```
  firebase deploy --only firestore:rules,firestore:indexes
  ```

## 3. Remote Config (feature flags)
- `feature_world_room_unlocked` stays **false** — World scoring auto-unlocks at
  5K users; the flag is a manual override for early testing only.

## 4. Flutter web
```
scripts/build-flutter-web.sh      # injects the RTW_* dart-defines from .env.local
firebase deploy --only hosting
```

## 5. iOS (App Store) — NOT one-command
Not published yet, so first submission has one-time setup.
- [ ] App Store Connect: app record, bundle id `today.readtheworld.app`,
      screenshots, privacy labels, metadata.
- [ ] Signing: distribution cert + provisioning profile (Apple Developer acct).
- [ ] **App Check = App Attest**: enable App Attest for the iOS app in Firebase
      → App Check, or live callables return `unauthenticated`. (Debug tokens are
      simulator-only — see §7.)
- [ ] Bump build number (`apps/app/ios/Runner` / pubspec) — last was 6.
- [ ] Build + upload:
  ```
  cd apps/app && flutter build ipa   # signed release
  ```
  then upload via Transporter / `xcrun altool` / fastlane, and submit for review
  (~1–3 days, human-gated).

## 6. Android (Play) — same shape
- [ ] Play Console app + signing (Play App Signing), store listing.
- [ ] `flutter build appbundle` → upload to a track → review.
- [ ] App Check: Play Integrity provider enabled for the Android app in Firebase.

## 7. Local iOS testing (not deploy, but the recurring gotcha)
- Run with `scripts/run-flutter-ios-live.sh <sim-udid>` (loads `RTW_*` from
  `.env.local`). A plain `flutter run` has no Firebase config and degrades
  silently.
- Debug builds enforce App Check via the **Apple debug provider**. Register the
  simulator's debug token in Firebase → App Check → iOS app → Manage debug
  tokens, or every callable (submit answers, verify email, create room + invite
  code, etc.) fails `unauthenticated`.

## 8. Post-publish follow-ups (deferred)
- Swap the store URLs in `apps/app/lib/v2/sheets/room_sheets.dart`
  (`_iosStoreUrl` / `_androidStoreUrl`) and flip `_appDownloadLink()` off the
  marketing fallback.
- World "who read it best" uses client-side search/pagination; true world-scale
  reveals will want server-side pagination.
