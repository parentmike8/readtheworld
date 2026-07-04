# Production Firebase + Data Goal

## Goal

Make Read the World production-functional with real Firebase authentication, live Firestore data, seeded question history, admin data management, and verified end-to-end production flows.

Take the work through implementation, testing, deployment, GitHub push, and a clear final status report.

## Context

- Repo: `/Users/michaelparent/development/Read the World`
- GitHub repo: `parentmike8/readtheworld`
- Firebase project: `read-the-world-74f2a`
- Primary app domain: `app.readtheworld.today`
- Marketing domain: `readtheworld.today`
- Admin domain: `admin.readtheworld.today`
- Short-link domain: `rtw.codes`
- Do not touch any CoVet GitHub, Google Cloud, Firebase, or work accounts/resources.
- Read `AGENTS.md` and `CLAUDE.md` files when present.
- Read the project docs before implementation, including `handoff.md`, the tech stack markdown, `read-score-logic.md`, and the admin design docs.

## Primary Objective

The app currently looks live but still behaves like local/demo data. Replace that with real production behavior:

1. Fully wire Firebase Auth.
2. Fully wire Firestore-backed app data.
3. Seed real daily questions, including roughly the last two months of historical questions.
4. Make admin able to manage questions and results.
5. Verify production flows using real accounts and data.
6. Deploy the working app, admin, functions, rules, and indexes to the production domains.

## Authentication Requirements

- Anonymous auth should remain disabled unless the onboarding model changes.
- Email/password sign-up and sign-in should work.
- Phone sign-in should work with SMS code verification.
- Google sign-in should work on web and iOS where possible.
- Apple sign-in should work on iOS and web where possible.
- Auth upgrade/linking should preserve user data.
- Logging out and logging back in should restore the correct user, not a hardcoded/demo user.
- Profile changes should persist to Firestore and reload correctly.
- Admin access should be protected so only `mike@readtheworld.today` can access admin for now.

## Data And Backend Requirements

- Replace remaining mock/demo/local-only data paths with production Firebase-backed repositories.
- Configure Firestore rules, indexes, functions, scheduled jobs, and seed scripts.
- Daily question lifecycle should work: scheduled/open, answer, predict, locked, reveal, scoring, and history.
- Seed the last roughly 60 days with realistic questions and closed results so history and insights can be tested.
- Ensure replay, archive, peek, party, and closed-question answers do not affect official score.
- Ensure one-submit enforcement and hidden results until reveal.
- Implement or verify Read Accuracy and Read Score from `read-score-logic.md`.
- Ensure account/profile demographics, preferences, streaks, category stats, friends/invites, and share links persist.

## Admin Requirements

- Admin at `admin.readtheworld.today` should use the latest admin designs.
- Admin should support drafting, scheduling, previewing, publishing, closing, recomputing, and viewing questions/results.
- Admin writes must be protected by custom admin claims and Firestore rules.
- If custom claim setup requires manual credentials or console actions, stop only when actually blocked and tell Michael exactly what to run or provide.

## Testing Requirements

- Use Firebase emulators where appropriate for rules/functions tests.
- Add or update tests for auth, rules, one-submit enforcement, hidden results, scoring, profile persistence, seeded history, and admin-only writes.
- Test production manually through the deployed app:
  - create a new account
  - log out and log back in
  - answer today's question
  - submit a prediction
  - update profile information
  - view history and insights
  - verify data is tied to the correct Firebase user
- Test iOS as far as possible.
- Skip Android for now.

## Deployment Requirements

- Deploy Firestore rules, indexes, functions, app hosting, and admin hosting as needed.
- Verify `app.readtheworld.today` and `admin.readtheworld.today` after deploy.
- Commit and push all changes to GitHub.
- Verify local branch parity with `origin`.
- Do not leave local servers or long-running processes active.

## Final Report Requirements

The final response should include:

- what was implemented
- what was deployed
- exact tests run
- production verification results
- remaining blockers or credentials still needed
- commit hash
- git parity status

## Credential Handling

If credentials, CLI auth, or console actions are needed, pause only when actually blocked and give exact step-by-step instructions. Prefer CLI/API setup when safe and available. Do not use or modify CoVet accounts.

## Expected Follow-Up After This Goal

This should be the last major engineering foundation step before a real beta, but not the last production-readiness step overall. Remaining beta readiness may still include App Store/TestFlight polish, privacy policy and terms review, App Check enforcement decisions, monitoring and alerts, notification QA, and Google Play once Android device verification is complete.
