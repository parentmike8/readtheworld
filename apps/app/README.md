# Read the World Flutter App

Flutter implementation of the Read the World product experience for iOS,
Android, and `app.readtheworld.today`.

## Local Development

The app runs in demo mode when Firebase dart defines are absent:

```sh
flutter run
```

For local simulator testing against the live Firebase project, keep the root
`.env.local` populated and run from the repository root:

```sh
npm run app:install:ios-sim
```

For an attached hot-reload session against live Firebase, run:

```sh
npm run app:run:ios-sim
```

For emulator-backed QA instead, run:

```sh
npm run app:run:ios-qa
```

Use the root build script for Flutter web deploy artifacts so the FCM service
worker is copied into `build/web`:

```sh
npm run app:build:web
```

Real Firebase builds need the `RTW_FIREBASE_*`, Google OAuth, App Check, and
web push values documented in `../../docs/setup.md`. Keep those values out of
git and run `npm run readiness:check` from the repository root before deploys.
