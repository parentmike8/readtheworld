# Read the World Setup

## Firebase and GCP

Use accounts/projects that are isolated from CoVet or any other work systems.
Do not deploy this app into an existing work Google Cloud organization, billing
account, Firebase project, GitHub org, or DNS zone.

1. Use the Firebase project `read-the-world-74f2a` (`863014025103`) under the `readtheworld.today` parent org.
2. Choose a US multi-region Firestore location before creating the database.
3. Copy `.firebaserc.example` to `.firebaserc` after `npm run accounts:check` is clean.
4. Create Firebase Hosting sites/targets:
   - `app` for `app.readtheworld.today`: `read-the-world-app-74f2a`
   - `links` for `rtw.codes`: `rtw-codes-74f2a`
   - `redirect` for `readtheworld.co`: `readtheworld-co-74f2a`
5. Copy `functions/.env.example` to `functions/.env.read-the-world-74f2a` and fill the app-link values before deploying Functions.
6. Deploy Firestore rules/indexes and Functions after credentials are configured.

After Firebase Auth is configured and the first admin user has signed in at least
once, grant the protected admin claim from a personal credential context:

```sh
npm run accounts:check
npm run admin:claim -- --email YOUR_ADMIN_EMAIL --project read-the-world-74f2a
```

To remove admin access:

```sh
npm run admin:claim -- --email YOUR_ADMIN_EMAIL --project read-the-world-74f2a --revoke
```

The script refuses to run against any project ID other than `read-the-world-74f2a`.

Current project targets:

- Firebase project: `read-the-world-74f2a` / `863014025103`.
- Parent org: `readtheworld.today`.
- Google account for cloud/Firebase operations: `mike@readtheworld.today`.
- Billing is linked to billing account `019A2B-4E7087-E90314` in the `readtheworld.today` org.
- Firestore default database is created in `nam5` (US multi-region), Native mode.
- Firestore rules/indexes have been deployed to the default database.
- Remote Config defaults have been deployed from `firebase/remoteconfig.template.json`.
- Firebase Auth providers enabled by config deploy: anonymous, email/password, and Google Sign-In.
- Firebase web app: `1:863014025103:web:e05141b61c1f8f156bbdfa`.
- Firebase Android app: `1:863014025103:android:66d363bc9b48c1596bbdfa`.
- Firebase iOS app: `1:863014025103:ios:b20d5ea02d9ec2c76bbdfa`.
- Firebase App Hosting backend: `read-the-world-web` in `us-central1`, URI `read-the-world-web--read-the-world-74f2a.us-central1.hosted.app`.
- Separate GCP console project noted by the user: `operating-tiger-500805-j4` / `782240188142`. Do not use it as the Firebase deploy target unless we intentionally assign it a role.
- Firebase CLI should be logged in as `mike@readtheworld.today` before Firebase deploys or app registration work.

## Domains

- `readtheworld.today`: Firebase App Hosting backend for the Next.js marketing/admin app.
- `admin.readtheworld.today`: same Next.js App Hosting backend, routed to `/admin` by `apps/web/src/proxy.ts`.
- `app.readtheworld.today`: Flutter web app on Firebase Hosting.
- `rtw.codes`: first-party short links and app links. Do not use Firebase Dynamic Links. Invite links currently expire after 90 days; result links expire after 30 days and only resolve while the target question is officially closed.
- `readtheworld.co`: 301 redirect to `https://readtheworld.today`.

## Admin Local Preview

The protected admin UI can be visually previewed with sample data before Firebase
credentials are configured by running the Next app in development with:

```sh
NEXT_PUBLIC_ADMIN_PREVIEW=true npm run dev -- --port 6211
```

This preview path is disabled in production builds. Real admin access still
requires Firebase Auth plus the `admin` custom claim.
Once signed in with that claim, the admin dashboard loads aggregate metrics and
recent result data through `getAdminOverview`; the question editor and waitlist
tools continue to use their separate protected callables. Settings feature
toggles are backed by Firebase Remote Config through `getAdminAppConfig` and
`setAdminFeatureFlag`, so they require a real Firebase admin session and are not
editable in unauthenticated preview mode.

Supported Remote Config feature flags:

- `feature_party_mode`
- `feature_friends`
- `feature_friends_leaderboard`
- `feature_result_sharing`
- `feature_onboarding_demographics`

Flutter keeps all five flags enabled by default when Remote Config is not
available. The checked-in `firebase/remoteconfig.template.json` mirrors those
defaults and should be published only from the isolated Read the World Firebase
project. Functions cache the published social/share flag values briefly and
fall back to these same defaults if Remote Config cannot be read.

## Account isolation checklist

- Use the `readtheworld.today` Google organization/account for Read the World cloud and Firebase work.
- Use a dedicated Read the World billing account or billing setup, separate from CoVet/work.
- Use a dedicated GitHub repo under a personal account or personal org.
- Run `firebase login:list`, `gcloud auth list`, and `gh auth status` before any deploy.
- Run `npm run accounts:check` before creating GitHub/Firebase/GCP resources or deploying; it is read-only and flags obvious CoVet/work-account context.
- If a CoVet account or any non-Read-the-World Google account is active in cloud/Firebase CLI, switch accounts or use a separate terminal/browser profile before continuing.
- Expected local CLI context before push/deploy:
  - GitHub active account: `parentmike8` (`gh auth switch --user parentmike8` when ready).
  - Google Cloud active account: `mike@readtheworld.today` (`gcloud config set account mike@readtheworld.today` after logging it in).
  - Firebase CLI account: `mike@readtheworld.today` (`firebase login` in the isolated browser/profile).
- Keep `.firebaserc` out of git and verify the project ID before every `firebase deploy`.
- Use a separate browser profile for Firebase Console, Google Cloud Console, GitHub, Apple Developer, and domain DNS setup if work sessions are also active.

Run the full deployment readiness check before pushing/deploying:

```sh
npm run readiness:check
```

This command is read-only. It verifies the active GitHub/GCloud/Firebase account
contexts, `.firebaserc` target IDs, Firebase config files, Remote Config
defaults, Flutter build defines, Next public Firebase env, App Hosting env
declarations, `admin.readtheworld.today` routing, and deployable Functions
runtime env for `rtw.codes` association files. It should fail locally until the
Read the World account contexts and real Firebase app values are in place.

Run the native readiness check before iOS/Android release work:

```sh
npm run native:check
```

This command is read-only. It verifies Flutter, Android app-link/orientation
metadata, iOS deployment targets, plist/entitlement syntax, CocoaPods, Xcode
first-launch status, installed iOS SDKs, and available Simulator runtimes. It
does not install Xcode components or run a build. If it reports that Xcode
first-launch or iOS Simulator runtimes are missing, fix Xcode from the personal
Read the World development context before retrying iOS builds.

## Mobile credentials

- iOS bundle ID: `today.readtheworld.app` unless changed before store submission.
- Android package ID: `today.readtheworld.app` unless changed before store submission.
- Configure Apple Sign In, Google Sign In, APNs, Play signing fingerprints, and App Check before public beta.
- Google Sign-In is enabled in Firebase Auth. The iOS URL scheme is already set in `Runner/Info.plist`.
- Google Sign-In requires Firebase Auth Google provider plus the OAuth client IDs from the isolated Read the World Firebase apps:
  - `RTW_GOOGLE_WEB_CLIENT_ID`: `863014025103-mvugvtqhvmtr4gliohs7ps806llplrsa.apps.googleusercontent.com`.
  - `RTW_GOOGLE_IOS_CLIENT_ID`: `863014025103-ckkb012rjcn036h23b3ipfdnmbv89rqg.apps.googleusercontent.com`.
  - iOS reversed client ID: `com.googleusercontent.apps.863014025103-ckkb012rjcn036h23b3ipfdnmbv89rqg`.
- Apple Sign In is wired through Firebase Auth's Apple provider and the iOS Sign in with Apple entitlement is checked into `Runner.entitlements`; enable the capability for the final Apple bundle ID in the Apple Developer account.
- `rtw.codes` is already declared in the Android App Links manifest and iOS Associated Domains entitlement. The Flutter app has a `/:code` route for installed-app opens, and the web resolver handles browser opens; do not add Firebase Dynamic Links.
  After Apple Team ID is final, copy `functions/.env.example` to `functions/.env.read-the-world-74f2a` and set `APPLE_TEAM_ID` plus `IOS_BUNDLE_ID` for the Function that serves `/.well-known/apple-app-site-association`.
  Keep `ANDROID_APP_LINKS_ENABLED=false` until Google Play signing is available; `/.well-known/assetlinks.json` will return `[]` during the web/iOS-only beta. When Android resumes, set `ANDROID_APP_LINKS_ENABLED=true`, keep `ANDROID_PACKAGE_NAME=today.readtheworld.app`, and set `ANDROID_SHA256_CERT_FINGERPRINTS`.
- App icons are generated from the brand-sheet `r.` mark with `npm run app:icons`. The generated PNGs are exact-size RGB assets with no alpha channel for App Store compatibility.
- Android release signing uses environment variables when present and falls back to debug signing for local builds:
  - `RTW_ANDROID_KEYSTORE_PATH`
  - `RTW_ANDROID_KEYSTORE_PASSWORD`
  - `RTW_ANDROID_KEY_ALIAS`
  - `RTW_ANDROID_KEY_PASSWORD`

## Flutter build-time configuration

Pass Firebase app values with `--dart-define` when building the Flutter app.
Keep these values sourced from the isolated Read the World Firebase project, not
from any CoVet or work project.

Required after Firebase apps are created:

- `RTW_FIREBASE_CONFIGURED=true`
- `RTW_FIREBASE_API_KEY`: web API key from the Firebase web app.
- `RTW_FIREBASE_APP_ID=1:863014025103:web:e05141b61c1f8f156bbdfa`
- `RTW_FIREBASE_ANDROID_API_KEY`: Android API key from the Firebase Android app.
- `RTW_FIREBASE_ANDROID_APP_ID=1:863014025103:android:66d363bc9b48c1596bbdfa`
- `RTW_FIREBASE_IOS_API_KEY`: iOS API key from the Firebase iOS app.
- `RTW_FIREBASE_IOS_APP_ID=1:863014025103:ios:b20d5ea02d9ec2c76bbdfa`
- `RTW_FIREBASE_SENDER_ID`
- `RTW_FIREBASE_PROJECT_ID`
- `RTW_FIREBASE_AUTH_DOMAIN`
- `RTW_FIREBASE_STORAGE_BUCKET`
- `RTW_GOOGLE_WEB_CLIENT_ID`
- `RTW_GOOGLE_IOS_CLIENT_ID`

Known project values:

- `RTW_FIREBASE_PROJECT_ID=read-the-world-74f2a`
- `RTW_FIREBASE_SENDER_ID=863014025103`
- `RTW_FIREBASE_AUTH_DOMAIN=read-the-world-74f2a.firebaseapp.com`
- `RTW_FIREBASE_STORAGE_BUCKET=read-the-world-74f2a.firebasestorage.app`

Required before public beta:

- `RTW_RECAPTCHA_ENTERPRISE_SITE_KEY` for Firebase App Check on web. Use the Firebase Console App Check setup for the `Read the World Web` Firebase app and register the production web domains before enforcing App Check.
- `RTW_WEB_PUSH_VAPID_KEY` for FCM web push tokens. Generate or copy it from Firebase Console > Project settings > Cloud Messaging > Web push certificates.
- `APPLE_TEAM_ID` for Universal Links. Use the Apple Developer Team ID that owns the final `today.readtheworld.app` bundle ID.
- `ANDROID_SHA256_CERT_FINGERPRINTS` for Android App Links once Android is enabled. Use the Play App Signing app-signing certificate SHA-256 fingerprint for production; add a debug or upload-key fingerprint separately only when needed for local testing.
- Flutter web includes `apps/app/web/firebase-messaging-sw.js` for FCM background messages.
  It uses Firebase Hosting reserved URLs, so `app.readtheworld.today` must stay on Firebase Hosting for that worker to auto-load the correct project config.

Example local web build:

```sh
npm run app:build:web -- \
  --dart-define=RTW_FIREBASE_CONFIGURED=true \
  --dart-define=RTW_FIREBASE_PROJECT_ID=read-the-world-74f2a \
  --dart-define=RTW_FIREBASE_API_KEY=... \
  --dart-define=RTW_FIREBASE_APP_ID=... \
  --dart-define=RTW_FIREBASE_SENDER_ID=863014025103 \
  --dart-define=RTW_FIREBASE_AUTH_DOMAIN=read-the-world-74f2a.firebaseapp.com \
  --dart-define=RTW_FIREBASE_STORAGE_BUCKET=... \
  --dart-define=RTW_RECAPTCHA_ENTERPRISE_SITE_KEY=... \
  --dart-define=RTW_WEB_PUSH_VAPID_KEY=...
```

Do not run the example build/deploy commands with a CoVet/work Firebase or GitHub session active.
