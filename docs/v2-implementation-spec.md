# Read the World v2 — Implementation Spec (Rooms Pivot)

Source of truth for UX/UI: `Daily Global Prediction Game v2/Read the World v2.dc.html`
(mobile prototype; its logic class defines interactions, copy, and animation timing).
This doc defines everything the prototype intentionally does not: backend rules, data
model, scoring, permissions, and how the design ports to web + admin.

Decisions below marked **[Mike]** came from product direction on 2026-07-01.
Decisions marked **[default]** are common-sense choices — flag anything to change.

---

## 1. Scope

| Surface | v2? | Notes |
|---|---|---|
| Mobile app (Flutter) | ✅ rebuild to v2 | The design file is the spec |
| Web app (Flutter web) | ✅ rebuild to v2 | Port mobile design responsively (§8) |
| Admin panel (Next.js) | ✅ extend | Question bank, world curation, room oversight, unlock control |
| Landing page (Next.js) | ❌ keep v1 | Update later **[Mike]** |
| Migration | none | No real users; delete existing auth users + user data, start day-one **[Mike]** |

## 1b. Design fidelity — 1:1 with the prototype **[Mike]**

The v2 prototype was hand-tuned; treat it as pixel- and feel-authoritative, not
directional. Concretely:

- **Inline styles are the spec.** Port values verbatim into `tokens.dart` /
  widget styles: exact px (padding, radii, sizes), font families/weights/
  letter-spacing, colors (oklch → hex for Flutter, keep oklch in comments).
- **Motion is the spec.** Reveal fill 1100ms ease-out-cubic (+150ms snap
  fallback), room reveal 1500ms with staggered per-question fills
  (`(t − 0.35 − i·0.14)/0.4`), party reveal 1000ms, card fling 280ms/380px,
  page fades per screen (`rwFadeUp .5s`).
- **Feel is the spec.** Swipe: dragX clamped ±170, commit at ±66, border tint at
  ±28, side-label opacity ramp over 110px, tilt = dx·0.04°. Meter: flip-side arms
  at pred ≤ 2 and fires on release; duo snap 0/100; party snap 100/(players−1).
- **Copy is the spec** — lift strings verbatim (verdict bands, sheet copy,
  button labels, empty states).
- QA: run the prototype in a browser next to the app, screen-by-screen
  (design-qa.md checklist pattern from v1); deviations only where a platform
  genuinely can't match, and note them.
- Where the prototype and this doc conflict on **UX/UI**, the prototype wins;
  on **logic/backend**, this doc wins (the prototype's data is fake).
- **Exception — swipe feel [Mike]**: the prototype's swipe isn't smooth enough.
  Keep its thresholds/visual language but implement native-quality gesture
  physics: velocity-aware fling (commit on fast flick even under the distance
  threshold), spring-back animation, 60/120fps direct-manipulation drag, and
  **haptics** — light tick when crossing the commit threshold (±66), medium
  impact on commit/lock, light tick on meter flip-arm (`HapticFeedback` on
  iOS/Android; no-op web).

## 2. Core model: Rooms

- A **room** is a group that plays 3 questions/day together. Types by member count:
  - **Solo (1)**: answer-only, no prediction, keeps streak. No room score.
  - **Duo (2)**: prediction is "did the other person match" — meter snaps 0/100.
  - **Group (3+)**: full loop — answer, predict % of the rest of the room that matched you.
  - **The World**: one global built-in room, curated daily by admin (§6). Answer-only
    until unlocked; unlock is a **manual admin control**, not automatic at 5K **[Mike]**.
    UI shows live progress toward the 5,000-player goal.
- Room properties (from design): name, color, tier (`work-safe` | `normal` | `mature`
  "After Dark"), category filters, custom-questions toggle, "reveal answers" default.
- **Roles [Mike]**: `creator` can edit settings, toggle/pull questions, delete the room.
  Any member can leave, invite, queue custom questions, and set their own per-room
  "show my answers" privacy. (Richer roles revisited later.)

## 3. Daily cadence (reuse existing)

Keep the existing scheduled rollover at **00:00 America/New_York** (`closeAndOpenDaily`)
**[Mike]** — extended to operate per-room:

1. **Close** yesterday's room sets: compute per-question `roomYesPct` from locked
   answers (all answers count, no quorum — a 1-answer question still reveals **[default]**),
   score each member (§4), update room scores/streaks, write reveal payloads.
2. **Assign** today's 3 questions per room from the bank (§5) + custom queue (§6).
3. World room: activate the admin-curated set for the new `dailyKey`; if none curated,
   fall back to bank selection and surface a warning in admin **[default]**.
4. Reveal UX: room's reveal is shown on first open after rollover (one-time animated
   screen per design, `revealSeen` flag), then lives in Room Detail / history.

## 4. Scoring (reuse existing engine)

- **Per-question accuracy** (unchanged, `scoring.dart` / `functions/src/scoring.ts`):
  `readAccuracy = clamp(100 − |prediction − actualShare|, 0, 100)`.
- **Room Read Score** — per-member, per-room Elo-like rating **[Mike: keep existing]**:
  starts at 1500; daily delta = `K × ((percentile − 0.5) / 0.5)` where percentile ranks
  the member's average accuracy for the day **within the room** (global percentile for
  The World once unlocked) **[default]**; K by member's total questions answered:
  32 (<10), 24 (<50), 16 (<150), else 12 — newer players catch up faster.
- Duo rooms score with the same formula (accuracy vs 0/100 actual). Solo rooms and
  locked-World answers are unscored (`answerOnly`).
- **Profile "average read"** = mean of the user's room scores (per design VM).
- **Streak** (per room): +1 for each consecutive day the member locked all of that
  room's questions; missing a day resets **[default]**.
- Replays/party never score (unchanged rule).

## 5. Question bank (new)

- **Seed source [Mike]**: Google Sheet
  `1h1QsQ5Mo_CuMvyEPQgQW4KWZHuYt77lEbVcUTZIH-4A` (~250 questions currently; target
  1,000+). Columns: Question, Option A, Option B, Categories (semicolon tags),
  Work Safe, Mature, Shape, Why It Works.
- `questionBank/{qid}`: `prompt`, `optA`/`optB`, `tags[]` (from Categories),
  `tier` (WorkSafe=TRUE → `work-safe`; Mature=TRUE → `mature`; neither → `normal`),
  `shape` (TASTE | CONFESS | MIRROR | GREY | TRADE | NORM | HABIT | BELIEF),
  `active`, `timesUsed`, `lastUsedAt`, `createdAt`.
- Room category chips map to a canonical tag set derived from the sheet's primary
  tags (Food & Drink, Technology, Work & Money, Travel, Social, Psychology,
  Relationships, Ethics, Entertainment, Lifestyle, Deep, Sex & Dating, Dark, …)
  **[default]** — the design's 8 placeholder categories are superseded.
- Daily selection also mixes **shapes** across the 3 picks when possible (avoid
  serving 3 CONFESS in one day) **[default]**.
- **Selection per room per day [Mike + default]**:
  1. Filter: `active`, tier ≤ room tier (After Dark includes normal + work-safe;
     work-safe rooms get only work-safe), category ∈ room categories.
  2. Exclude any question the **room** has already used (`rooms/{id}/usedQuestions`).
  3. Prefer questions **no current member has seen in any of their rooms**, then
     least-`timesUsed` — gives variety across players; hard rule is per-room no-repeat.
  4. Custom queue injection — **dynamic by queue depth [Mike]**: room-wide queue of
     1–4 → 1 custom today; 5–9 → 2; 10+ → 3. Always at least 1 when anything is
     queued (FIFO). Deeper queues drain faster so members can queue again; customs
     are made to last when the queue is shallow.
- Admin: bank CRUD + bulk import (paste/CSV), filters by tier/category/usage.

## 6. Custom questions & safety

- Queue per member per room, **cap 10 queued** (design). Queued prompts are
  not attributed in the queue; author name shows once live. Author can
  edit/delete queued items.
- **Flagging** (live custom questions only **[Mike confirmed]**): one flag from any
  member pulls the question for the whole room for the day, author gets a
  notification, question is replaced next rollover (not re-served). Flags visible in
  admin. (Design has this: Flag sheet on the play surface — "One flag pulls a custom
  question for the whole room today, no questions asked. The author is notified.")
- **After Dark**: join flow shows consent sheet (design). Profile-level "After Dark"
  toggle gates it globally; joining via the consent sheet sets it **[default]**.
- World room questions: admin-curated 3/day (§3), each shows a live answer count with
  a reveal threshold (1,000 in design — make it a per-question admin field).

## 7. Firestore schema (v2 additions)

```
questionBank/{qid}                      // §5
rooms/{roomId}
  name, color, tier, cats[], customEnabled, createdBy, createdAt,
  memberCount, isWorld, inviteCode, streak-agnostic config only
rooms/{roomId}/members/{uid}
  role: 'creator'|'member', joinedAt, revealMine: bool,
  roomScore, streak, lastPlayedDailyKey     // denormalized for boards
rooms/{roomId}/days/{dailyKey}
  questions: [{qid, prompt, optA, optB, cat, tier, custom, authorUid?, pulled?}]
  status: 'live'|'closed', results?: [{qid, yesPct, answers}]
rooms/{roomId}/days/{dailyKey}/answers/{uid}
  picks: [{qid, side, prediction|null}], lockedAt, scored, accuracyAvg, scoreDelta
rooms/{roomId}/queue/{itemId}           // custom questions, authorUid, text, optA/B
users/{uid}                             // keep; drop v1 friends model
users/{uid}/roomStats/{roomId}          // score history per room (for profile)
links/{code}                            // reuse short-link infra, type: 'room'
flags/{flagId}                          // audit trail
```

- Security rules mirror v1 patterns: members read their rooms; answers write-once per
  day via callable; results/reveal data only readable when day is closed; bank and
  world curation admin-only. Room settings writes: creator only.
- v1 collections retired: `questions` (replaced by bank + room days), `friends`,
  global `leaderboards` (boards are per-room now), `answerDrafts` (replaced by
  per-day draft docs if needed — keep same mechanism, scoped per room-day).

## 8. Porting mobile design → web (Flutter) and admin

The design file is mobile-only (402×874) **[Mike: must port nicely]**:

- **Play surfaces** (Today deck, predict, reveal, party): keep the phone-column layout
  centered (~420–480px) on wide screens — same approach the v1 web app already uses.
  Swipe gestures get click/tap + keyboard (←/→) equivalents on web.
- **Rooms home**: single column on mobile; 2-col card grid ≥820px with World hero
  spanning full width.
- **Room detail / profile / history**: centered 760px column (existing web pattern).
- **Bottom sheets** → centered modal dialogs ≥820px.
- **Nav**: bottom tabs (Today / Rooms / Party) on mobile; existing top-bar pattern on
  web with the same three + avatar.
- **Admin (Next.js)** new views: Question Bank (CRUD/import), World Curation (pick 3
  per upcoming day + thresholds), Rooms overview (count, activity, flags), and a
  **World unlock** control (Remote Config flag `feature_world_room_unlocked`) next to
  the live player count **[Mike]**.

## 9. Onboarding & auth

- Keep existing auth (email/Google/Apple). New v2 onboarding per design: welcome →
  simulated room intro → Day-1 demo (3 questions, local) → simulated next-day reveal →
  Day-2 demo → score payoff → World teaser → create/join first room.
- Demo is fully client-side (no server writes). Demographics collection is dropped
  from onboarding (not in v2 design); editable later in profile **[default]**.

## 10. Party mode

Pass-the-phone (per design): setup (players 1–20, rounds, topic, order) →
swipe/pick per player → per-question reveal with player tally → summary.
- **Scoring is session-local** (per-player points within the game, per design's
  formula) — never touches profile/room Read Scores **[Mike]**.
- **Questions sync from the cloud bank**: pool is cached locally so party works
  offline, refreshes when connected, and rotates played questions out across
  playthroughs for variety **[Mike]**.

## 11. Keep / retire from v1

| Keep | Retire |
|---|---|
| Theme/tokens, shared widgets, fonts | Single global daily question flow |
| Auth + App Check + short links (`rtw.codes`) | Friends list & friend comparisons |
| Scoring engine + K-factor | Global leaderboard screens |
| 00:00 ET rollover + notification plumbing | Insights screen (v2: profile + room boards) |
| Admin shell, feature-flag system | v1 History tab (history is per-room sheet) |
| Landing page (as-is) | v1 onboarding demographics steps |

- Notifications retarget: daily reminder (existing) + "your rooms revealed" after
  rollover + flag notice to authors. Reveal-ready per-room push reuses existing infra.

## 12. Build order

1. **Spec sign-off** ← you are here
2. Data layer: schema, rules, bank seed (~100 starter questions to develop against)
3. Functions: rollover v2, room CRUD/join/leave, submit/lock, custom queue, flags
4. Flutter: theme reuse → Rooms home → Room detail/reveal → Today deck + play loop →
   sheets → profile/onboarding → party → web responsive pass
5. Admin: bank, world curation, unlock control, rooms overview
6. Reset: delete existing auth users + Firestore user data **[Mike approved]**
7. QA pass: rules tests, functions tests, widget tests, manual loop across 2 accounts

## Open items (deferred, non-blocking)

- Room member cap (default none; revisit at scale)
- Question bank authoring pipeline beyond admin CRUD (bulk generation/review)
- World room behavior after unlock at scale (percentile pool size)
- Landing page v2, store screenshots
