# Read the World Tech Stack

## Recommended Stack

The product should use a cross-platform app stack with a separate lightweight marketing website.

## Product App

Use **Flutter** for the main application.

Target platforms:

- iOS
- Android
- Web app / logged-in browser experience

Flutter is a good fit because the product is visually custom, interaction-light, and animation-driven. The app does not need to perfectly mimic native iOS or Android system UI. It needs to feel smooth, polished, and consistent across platforms.

The app experience should include:

- daily question flow
- answer selection
- prediction slider
- locked submission state
- delayed result reveal
- Read Accuracy display
- Read Score display
- history / archive
- insights
- friend leaderboard
- push notification preferences

## Marketing Website

Use a separate web stack for the public landing page.

Recommended:

- **React / Next.js**
- Static or mostly static landing page
- Hosted separately from the Flutter app if desired

The public website should focus on:

- explaining the product
- waitlist / email capture
- app store links once available
- shareable brand URL
- basic SEO
- press / about page later

The marketing website does not need to be built in Flutter. Flutter Web is acceptable for the logged-in app, but a landing page is better handled by a standard web framework because it will be easier to optimize for SEO, speed, metadata, responsive landing layouts, and marketing iteration.

## Backend

Use **Firebase** as the primary backend platform.

Firebase is the best default because this product needs mobile-app infrastructure more than complex custom backend infrastructure.

Core Firebase services:

- Firebase Auth
- Cloud Firestore
- Cloud Functions
- Firebase Cloud Messaging
- Firebase Hosting
- Firebase Analytics
- Firebase Remote Config
- Firebase Crashlytics
- Firebase Performance Monitoring

## Firebase Auth

Use Firebase Auth for account creation and login.

Supported auth methods:

- anonymous user session for immediate onboarding
- Apple login
- Google login
- email login or magic link, if desired

The app should allow users to start quickly without heavy onboarding. Anonymous auth can be upgraded later to a permanent account.

## Firestore

Use Cloud Firestore as the primary app database.

Firestore should store:

- users
- daily questions
- question options
- user answers
- user predictions
- official result snapshots
- Read Accuracy per question
- Read Score history
- category stats
- streaks
- friend relationships
- leaderboard snapshots

The data model should favor precomputed and denormalized records where needed. Do not rely on expensive live aggregation queries for results, leaderboards, or rankings.

## Cloud Functions

Use Cloud Functions for backend logic that should not run on the client.

Required functions:

- close the active daily question
- lock official votes
- calculate official results
- calculate each user's Read Accuracy
- calculate daily percentiles
- update Read Scores
- update streaks
- update category stats
- generate leaderboard snapshots
- open the next daily question
- send notifications

Scheduled functions should run on the official daily cadence.

## Firebase Cloud Messaging

Use Firebase Cloud Messaging for push notifications.

Notification types:

- today's question is live
- yesterday's result is ready
- streak reminder
- friend passed your Read Score
- special event question is live

Notifications should be opt-in and carefully restrained. The main valuable notification is likely:

```text
Yesterday's result is ready.
```

## Firebase Analytics

Use Firebase Analytics for early product analytics.

Track key events:

- app_open
- view_daily_question
- submit_answer
- submit_prediction
- lock_prediction
- view_reveal
- view_history
- answer_past_question
- share_result
- invite_friend
- join_friend_group
- notification_opt_in
- streak_continued
- streak_lost

Important metrics:

- D1 retention
- D7 retention
- D30 retention
- daily question completion rate
- answer-to-prediction completion rate
- reveal return rate
- notification opt-in rate
- share rate
- archive engagement
- friend invite conversion

Amplitude or PostHog can be added later if deeper product analytics are needed, but Firebase Analytics is enough for the MVP.

## Remote Config

Use Firebase Remote Config to control app behavior without requiring app releases.

Configurable values:

- daily question release time
- reveal time
- notification copy
- onboarding copy
- scoring constants
- minimum response threshold for scored questions
- feature flags
- category visibility
- experiment variants

Remote Config is useful because the team will likely tune scoring, copy, onboarding, and notification timing frequently.

## Crashlytics And Performance

Use Crashlytics and Performance Monitoring for mobile app quality.

Track:

- crashes
- app startup time
- slow screens
- network performance
- failed submissions
- failed reveal loads

The daily flow should feel reliable. A failed answer submission or broken reveal would be especially damaging to trust.

## Hosting

Use Firebase Hosting for:

- Flutter web app
- web fallback routes
- admin preview tools if needed

Use Vercel, Netlify, or similar for the public landing page if the website is built in Next.js.

Either approach is acceptable:

```text
readtheworld.today -> marketing website
app.readtheworld.today -> Flutter web app
```

or:

```text
readtheworld.today -> marketing website
readtheworld.today/app -> Flutter web app
```

The cleaner long-term structure is likely:

```text
readtheworld.today
app.readtheworld.today
```

## Admin / Editorial Tool

The team will need an internal admin interface for question management.

This can be built as:

- a simple React admin app
- a lightweight Firebase-connected internal dashboard
- Retool / Appsmith / similar tool for MVP

Admin features:

- create questions
- assign category
- create answer options
- set publish date
- preview question
- approve question
- lock / unlock draft status
- view response counts
- view result snapshots
- flag sensitive questions
- manage event-based questions

The admin tool does not need to be in Flutter.

## Suggested Architecture

```text
Flutter App
  -> Firebase Auth
  -> Firestore
  -> Cloud Functions
  -> Firebase Cloud Messaging
  -> Firebase Analytics

Next.js Landing Site
  -> Waitlist capture
  -> SEO pages
  -> App store links

Admin Tool
  -> Firestore
  -> Cloud Functions
```

## MVP Scope

Build first:

- Flutter app for iOS and Android
- Flutter web app if low-cost to include
- Firebase Auth
- Firestore data model
- daily question flow
- prediction flow
- result reveal
- Read Accuracy
- Read Score
- basic history
- basic push notifications
- simple admin question management
- React / Next.js landing page

Defer:

- complex social graph
- public comments
- AI summaries
- cash payouts
- advanced demographic weighting
- complex moderation systems
- native iOS and Android separate builds
- full custom backend

## Technical Principle

The app should avoid unnecessary infrastructure complexity until the daily habit is proven.

The stack should optimize for:

- fast iteration
- cross-platform reach
- polished mobile feel
- reliable daily scheduling
- easy notifications
- simple analytics
- low backend maintenance

Recommended final stack:

```text
App: Flutter
Landing Page: React / Next.js
Backend: Firebase
Database: Cloud Firestore
Server Logic: Cloud Functions
Notifications: Firebase Cloud Messaging
Analytics: Firebase Analytics
Hosting: Firebase Hosting + Vercel/Netlify as needed
```
