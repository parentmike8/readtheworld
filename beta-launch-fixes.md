# Beta Launch Fixes

Working checklist for the launch-readiness issues found in the full code pass.

## P1

- [x] Restore today state reliably.
  - `apps/app/lib/app_state.dart`
  - Fixed: answer and draft listeners now notify on state changes, in-progress answers are persisted to `answerDrafts`, locked answers cannot be restarted, and drafts are cleared after successful lock.

- [x] Clear all user data completely.
  - `functions/src/index.ts`
  - Fixed: `clearMyData` now deletes `answerDrafts` and `notificationTokens` and resets notification opt-in state.

- [x] Enforce a single live question.
  - `functions/src/index.ts`
  - `apps/app/lib/app_state.dart`
  - `apps/web/src/app/page.tsx`
  - `apps/web/src/lib/shareCards.ts`
  - Fixed: admin live writes now reject another live question, and live reads order by latest `publishAt`.

- [x] Wire `rtw.codes` to the real short-link resolver.
  - `firebase.json`
  - `functions/src/index.ts`
  - `apps/app/lib/app_state.dart`
  - Fixed: `rtw.codes/**` now rewrites to `resolveShortLink`, app share/invite methods prefer `shortUrl`, and app-link well-known routes remain function-backed.

## P2

- [x] Make friends data live or hide incomplete friend-answer comparison.
  - `functions/src/index.ts`
  - `apps/app/lib/app_state.dart`
  - `apps/app/lib/screens.dart`
  - Fixed: leaderboard recompute fans profile/score updates into friend rows, and reveal loads real shared friend answers through `getFriendAnswerComparisons`.

- [x] Replace locked-screen fake countdown.
  - `apps/app/lib/screens.dart`
  - `apps/app/lib/app_state.dart`
  - Fixed: countdown is derived from the live question `closeAt` and refreshes once per second while locked.

- [x] Remove hardcoded June 2026 dates.
  - `apps/app/lib/screens.dart`
  - Fixed: DOB uses current date and history defaults to the latest available/current month.

- [x] Finish notification behavior.
  - `apps/app/lib/app_state.dart`
  - `apps/app/lib/main.dart`
  - Fixed: notification reminders default to off, sign-out resets to off, and notification taps route through the app router with a route whitelist.

- [x] Enforce App Check on backend callables.
  - `functions/src/index.ts`
  - `apps/web/src/lib/appCheck.ts`
  - `apps/web/apphosting.yaml`
  - Fixed: every callable uses `enforceAppCheck`, Next marketing/admin initialize App Check, and App Hosting has the public reCAPTCHA Enterprise key.

## P3

- [x] Hide or wire static admin settings controls.
  - `apps/web/src/components/AdminPanel.tsx`
  - Fixed: inert timing/category/analytics controls are now static labels or removed, and schedule copy now matches click-to-edit behavior.

- [x] Fix question library "New question" action.
  - `apps/web/src/components/AdminPanel.tsx`
  - Fixed: the editor now opens below the library header, scrolls into view, pre-fills a draft question ID/category/options, and allows unscheduled draft saves.

## Verification

- [x] `npm run accounts:check`
- [x] `npm run readiness:check`
- [x] `npm run native:check`
- [x] `npm run web:lint`
- [x] `npm run web:build`
- [x] `npm run functions:build`
- [x] `npm run functions:test`
- [x] `npm run rules:test`
- [x] `npm run app:analyze`
- [x] `npm run app:test`
- [x] `npm run app:build:web`
