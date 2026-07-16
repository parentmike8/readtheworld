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
cd .. && npm run deploy:functions
```
- [ ] Watch logs for the first `rolloverRooms` / lock after deploy.

## 2. Firestore rules / indexes
- **No rules or index changes this session.** Deploy these only if their files
  actually change in a future release:
  ```
  firebase deploy --only firestore:rules,firestore:indexes
  ```

## 3. Remote Config (feature flags)
- `feature_world_room_unlocked` stays **false** — World scoring auto-unlocks at
  5K users; the flag is a manual override for early testing only.

## 4. Flutter web
```
npm run deploy:app  # builds with production dart-defines, then deploys hosting:app
```

## 5. iOS (App Store) — NOT one-command
The App Store record already exists. This is a new build submission for the
existing app.
- [ ] Signing: distribution cert + provisioning profile (Apple Developer acct).
- [ ] **App Check = App Attest**: enable App Attest for the iOS app in Firebase
      → App Check, or live callables return `unauthenticated`. (Debug tokens are
      simulator-only — see §7.)
- [ ] Bump the build number in `apps/app/pubspec.yaml`.
- [ ] Build the archive/IPA with `scripts/build-flutter-ios-release.sh`. Never
      archive with bare `flutter build ipa` or from Xcode Organizer directly:
      the archive inherits `DART_DEFINES` from whatever flutter command ran
      last (a prior QA run bakes in the emulator config; a plain `flutter run`
      bakes in nothing) and ships silently broken. The script validates
      `.env.local`, injects the defines, and asserts they landed in the build.
      Also do not export an unsigned Flutter archive for upload: that path can
      silently omit Apple Sign-In, APNs, and associated domain entitlements
      from the final app signature.
- [ ] Before upload, verify the signed archive or exported IPA and its expected
      build number (use the current build number from `apps/app/pubspec.yaml`):
  ```
  npm run ios:release-check -- apps/app/build/ios/archive/Runner.xcarchive <build-number>
  # or
  npm run ios:release-check -- apps/app/build/ios/ipa/*.ipa <build-number>
  ```
  This gate must report Apple Sign-In, production push notifications,
  `applinks:rtw.codes`, a valid distribution signature, and the production
  Firebase config baked into the Dart snapshot before upload.
- [ ] Upload the verified signed archive:
  ```
  xcodebuild -exportArchive \
    -archivePath apps/app/build/ios/archive/Runner.xcarchive \
    -exportPath apps/app/build/ios/upload \
    -exportOptionsPlist apps/app/ios/ExportOptions-AppStore.plist \
    -allowProvisioningUpdates
  ```

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
