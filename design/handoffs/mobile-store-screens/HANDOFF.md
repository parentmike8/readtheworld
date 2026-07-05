# Read the World — Flutter + Firebase Handoff

A developer/LLM spec for porting the HTML prototype to a native **Flutter** app backed by **Firebase**. The `.dc.html` files in this archive are the **source of truth for layout and behavior** — read them, but rebuild natively. Do **not** transpile HTML to Flutter widgets literally.

> **Core product promise:** A daily app where people test how well they understand the world by answering one shared question, predicting what everyone else will think, and building a long-term profile of their beliefs and prediction accuracy.

---

## 0. Files in this archive

| File | What it is | Use it for |
|---|---|---|
| `Read the World.dc.html` | **Mobile app** (the canonical product) | Screen layouts, flows, the logic class (`class Component extends DCLogic`) = state model + behavior |
| `Read the World - Web.dc.html` | Responsive **web** version | Web/desktop layout (top-bar nav, side-by-side, centered column) |
| `Read the World - Landing.dc.html` | Marketing **landing page** | Public site — separate from the app |
| `Read the World - Login.dc.html` | **Auth screens** (mobile + web, sign-in + create) | Login/onboarding entry |
| `Read the World - Brand.dc.html` | **Brand sheet** | Logo, wordmark, app icon, tokens |

In each `.dc.html`: markup lives between `<x-dc>…</x-dc>`; the **logic class** is in the `<script type="text/x-dc">` block at the bottom. `renderVals()` returns the view-model; the handlers above it are the interactions. Inline `style="…"` values ARE the design tokens.

---

## 1. Brand & design tokens

### Color (CSS authored in oklch — hex equivalents for Flutter)
| Token | Role | Hex |
|---|---|---|
| Paper | app background | `#F3F0E9` |
| Paper (alt band) | section bg | `#EDE9E0` |
| Card | surfaces / tiles | `#FBFAF6` |
| Ink | primary text / dark surfaces | `#211F1A` |
| Ink-2 | dark card alt | `#2B2820` |
| Border | hairlines / inputs | `#E4DFD4` / `#E0DACE` |
| Sub text | secondary text | `#6E6A60` |
| Muted / mono | labels, captions | `#8A8475` |
| Faint | tertiary | `#A89F8C` |
| **You-blue** (primary accent) | the user / "you" | `#3E5BA0` (≈ `oklch(0.50 0.10 256)`) |
| You-blue tint | selected fill | `rgba(62,91,160,0.10)` |
| **World-terracotta** (secondary accent) | the world / results | `#B06A47` (≈ `oklch(0.55 0.105 47)`) |
| Danger | destructive (remove) | `#B0432F` (≈ `oklch(0.55 0.155 25)`) |
| On-dark blue | accents on ink | `#8FA6D6` (≈ `oklch(0.70 0.10 256)`) |
| On-dark clay | accents on ink | `#C58A5E` (≈ `oklch(0.62–0.70 0.11 47)`) |

The whole product is built on **"you (blue) vs. the world (terracotta)"** — keep that meaning consistent everywhere.

### Type (all Google Fonts — use `google_fonts` package)
| Family | Role | Notes |
|---|---|---|
| **Newsreader** (serif) | the hero/voice: questions, big numbers, headings | weight 500 mostly; tight negative letter-spacing (≈ -0.5 to -1.4 at large sizes); italics used sparingly |
| **Hanken Grotesk** (sans) | all UI: buttons, body, labels-in-sentences | 400/500/600/700 |
| **IBM Plex Mono** | eyebrows, metadata, stat labels, countdowns | uppercase, letter-spacing ~1.4–2px, sizes 10–12 |

### Shape & spacing
- Radii: cards `18–24`, tiles `15–18`, inputs `13–14`, buttons `14–16`, pills `20–22`, full circles for avatars/pins.
- Card pattern: `#FBFAF6` bg + `1px #E4DFD4` border (+ soft shadow on elevated/marketing cards only).
- Generous whitespace; screens cap content width on web (~`760px` app column, hero/sections `1080px`).
- Min tap target 44px.

### Logo
Wordmark **`read the world.`** in Newsreader 500, with the **period in terracotta**. App icon: lowercase **`r.`** (terracotta dot) on ink, or a blue tile — see `Read the World - Brand.dc.html`. (`rtw.` exists as a text monogram for tight spots; `r.` is the icon.)

---

## 2. The core loop (most important behavior)

Everyone worldwide gets the **same single question per day**. Each day the user does two things, then waits:

1. **Answer** — their own Yes/No (or Choose-One) answer. Private. "Just input."
2. **Predict** — what **percentage of people will pick the same answer they did** (0–100). They never predict the full distribution — only the share who match their own choice.
3. **Lock** — answer + prediction are locked for the day.
4. **Reveal (next day)** — when the new question drops, yesterday unlocks: shows the world's actual %, the user's answer, their prediction, and their accuracy score.

Habit loop: open → see today's question → answer → predict → return next day → reveal + score + streak + new question.

### Question types (MVP)
- **Agree / Disagree** (Yes / No)
- **Choose One** (predefined options)

Either way the two actions are identical (answer, then predict the % who chose the same). Build the model to support both; the prototype demonstrates Yes/No.

### Scoring — "Read Score" (per-question accuracy)
From the logic class. Per question:

```
sameWorld = (answer == 'Yes') ? worldYesPct : 100 - worldYesPct   // % of world who matched the user's side
gap       = abs(sameWorld - userPrediction)
readScore = clamp(100 - round(gap * 1.4), 0, 100)                 // shown as “/100” on reveal
```

(The seeded demo history uses a `*1.35` factor clamped to 71–99 purely to look plausible; **use `*1.4`, clamp 0–100** as the real per-question accuracy.)

**Long-term "Read Score"** (the leaderboard number, e.g. `1,840`) is the user's cumulative skill rating — it rises/falls after every completed question based on prediction accuracy (not whether they were in the majority), creating durable differentiation. Exact aggregation is open; a running points total or rating (e.g. Elo-like, or sum of daily accuracy deltas) is fine. Track it globally, by category, by region, and among friends. Rewards reading society, not agreeing with it.

Rules to preserve:
- Reward **accuracy of the prediction**, not siding with the majority.
- Changes after **every** completed question.
- Reflects long-term ability, not luck.
- **Replays / peeks of closed questions do NOT count** toward score (see History/Party).

---

## 3. Screens → Flutter mapping

Read each screen's markup + the matching `is<Screen>` flag in `renderVals()`. Screen state in the prototype is a single `screen` string; in Flutter use your router (go_router) with these routes.

| Screen | Route | Key widgets / notes |
|---|---|---|
| **Onboarding** | `/onboarding` | Welcome → About-you (date-of-birth picker, gender chips, country select; each optional w/ "Prefer not to say") → straight to Today. No "all set" interstitial. |
| **Today / Answer** | `/today` | Eyebrow (category · date) → hero "Can you read the world today?" → THE QUESTION → Yes/No tiles. Mobile: answer then tap "Now read the world →". Web: same focused one-at-a-time flow. |
| **Predict** | `/today/predict` | Big serif `NN%` + custom slider + dynamic phrase ("Split down the middle", "A clear majority"…) + "Lock in my prediction". Back = "Change my answer". |
| **Locked** | `/today/locked` | Confirmation, your answer + prediction, **live counter** ("185,053 answered today"), countdown to next drop, buttons: *See yesterday's result* + *View history*. |
| **Reveal** | `/reveal` | The magic moment. Animated spectrum bar fills to world %; your guess pin; "84% also said Yes. You guessed 71%." → Read Accuracy /100 + Read Score delta + streak. Share button. Handles three states: scored / peeked-no-answer / replay. |
| **History** | `/history` | Category filter chips + **month calendar** (filled dot = answered, hollow ring = missed; tap a day) + list of past cards. "Party" entry button. Tapping a missed day → answer-anyway flow (with "skip to result"). |
| **Party mode** | `/party` | Setup (topic, month multi-select, all/unanswered, "just reveal" vs "answer & predict", shuffled/chronological) → card deck → reveal per card → summary. Great on a shared screen. Answering new questions here DOES save to the user's answers; closed/replayed ones don't score. |
| **Insights** | `/insights` | Long-term Read Score + rank, "you read best / you misjudge" categories (bars), over/under-estimation tendency, **Friends leaderboard** (swipe-to-remove, per-friend answer-visibility toggle), invite (shareable link). |
| **Profile / Account** | `/account` | Avatar (color), display name, daily-reminder toggle, email, change password, **About you** (editable demographics), restart onboarding, log out, clear data. |
| **Login / Create** | `/auth` | Email + password, Google/Apple, show/hide password, sign-in ↔ create toggle, forgot password. See Login file (mobile + web). |

Interaction notes:
- **Prediction slider is custom** — a track + filled portion + draggable pin. Build with `GestureDetector`/`Listener` + `Stack`, not Material `Slider` (you need the big serif number, dynamic label, and exact styling).
- **Reveal animation** = `AnimationController` (~1.5s, ease-out cubic) animating the world-% fill and the counting numbers. Provide a reduced-motion fallback that jumps to final values.
- **Live "answered today" counter** ticks up periodically (cosmetic in prototype; back with a real/approximate Firestore count or a server estimate).
- **Friends list**: swipe-left to reveal Remove; tap a friend to toggle whether they see your actual answers (per-friend privacy).
- **Bottom nav** (mobile): Today / History / Insights. **Web**: sticky top bar with the same three + avatar → account.

---

## 4. Suggested Firestore data model

```
questions/{questionId}
  date: timestamp (the day it's the daily)         // one per day, same for everyone
  category: string                                 // Technology, Science, Money, ... (NOT "Canada")
  type: 'binary' | 'choice'
  prompt: string
  options: [string]                                // ['Yes','No'] for binary
  status: 'scheduled' | 'live' | 'closed'

dailyResults/{questionId}                          // written after close (aggregates only)
  totalAnswers: number
  distribution: { Yes: number, No: number }        // or per-option counts
  worldYesPct: number                              // convenience for binary

users/{uid}
  displayName: string
  avatarColor: string
  email: string
  demographics: { birthdate: 'YYYY-MM', gender: string|null, country: string|null }  // each optional
  readScore: number                                // long-term rating
  streak: number
  lastAnsweredDate: date
  dailyReminder: bool
  createdAt: timestamp

users/{uid}/answers/{questionId}
  answer: string                                   // 'Yes' | option
  prediction: number                               // 0–100, % who match their answer
  lockedAt: timestamp
  scored: bool                                     // false for replays/peeks of closed Qs
  readScoreDelta: number                           // applied at reveal
  source: 'daily' | 'party-replay'

users/{uid}/categoryStats/{category}
  accuracyAvg: number
  count: number
  overUnderBias: number                            // +/- tendency to over/underestimate agreement

friends/{uid}/{friendUid}
  sharesAnswersWithMe: bool
  answerVisibilityToThem: 'scores' | 'answers'     // per-friend privacy the user controls

invites/{code}  ->  uid                            // shareable invite link (read.world/u/<handle>)
```

Rules of thumb:
- Clients **write their own answer/prediction**; aggregate counts and `worldYesPct` are computed server-side (Cloud Function on question close, or incremental counters) so results can't be reverse-engineered before reveal.
- **Never expose `dailyResults` for a question until it's closed** (enforce in security rules) — the delayed reveal is the whole game.
- Compute `readScoreDelta` server-side at close to prevent tampering.
- Leaderboards: maintain denormalized aggregates (global / per-region from `demographics.country` / per-category / friends) rather than querying all answers.

---

## 5. Out of scope for v1 (do not build)
Cash payouts / prediction-market mechanics · open comment sections · AI-generated explanation summaries · user-created public polls · multiple simultaneous daily questions.

---

## 6. How to drive Codex
1. Point it at the `.dc.html` source + the screenshots; tell it these are the **spec**, to rebuild natively in Flutter (Material 3 off-brand defaults disabled; theme from the tokens above).
2. Build the **design system first** (ThemeData + a `tokens.dart` with the colors above + `google_fonts` text styles + shared widgets: `RtwButton`, `AnswerTile`, `PredictionSlider`, `SpectrumBar`, `QuestionCard`, `StatLabel`).
3. Then screen by screen, in loop order: Onboarding → Today → Predict → Locked → Reveal → History → Insights → Party → Account → Auth.
4. Wire Firebase last (Auth, Firestore, the question-of-the-day fetch, the close/reveal Cloud Function, scoring).
5. Verify the **reveal animation** and **custom slider** feel right — they're the signature interactions.
