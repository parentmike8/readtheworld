# Read the World Scoring Logic

## Purpose

The app uses two related but separate scoring concepts:

- **Read Accuracy**: how close a user was on one specific question.
- **Read Score**: the user's long-term skill rating compared to everyone else.

Read Accuracy should be simple and explainable. Read Score should behave like a rating that can move up or down over time based on prediction performance.

## Core User Flow

For each daily question, the user completes two actions:

1. Select their personal answer.
2. Predict what percentage of the world will also select that same answer.

Example:

Question: `Would you want to know the exact date you will die?`

User answer: `No`

User prediction: `5% of the world will also say No`

After the official answer window closes, the app calculates:

- the actual percentage of users who selected the same answer
- the user's Read Accuracy for that question
- the user's Read Score movement

## Official Window

Only answers submitted during the official question window should affect:

- the official public result
- Read Accuracy
- Read Score
- category scoring
- leaderboards

Late answers may be allowed for practice, archive play, onboarding, or social use, but they should not change the locked result or impact official scoring.

## Read Accuracy

Read Accuracy is calculated per question.

It measures how close the user's prediction was to the actual share of users who selected the same answer.

### Formula

```text
actual_share = votes_for_user_answer / total_official_votes
prediction_error = abs(user_predicted_share - actual_share)
read_accuracy = 100 - prediction_error
```

Clamp `read_accuracy` between `0` and `100`.

### Display

Display Read Accuracy as an integer out of `100`.

Example:

```text
Actual: 16% also said No
User guessed: 5%
Prediction error: 11 percentage points
Read Accuracy: 89 / 100
```

### Applies To Both Question Types

| Question Type | User Answer | User Prediction | Actual Share | Read Accuracy |
|---|---|---:|---:|---:|
| Agree / Disagree | No | 5% also said No | 16% | 89 |
| Choose One | NVIDIA | 42% chose NVIDIA | 35% | 93 |

## Read Score

Read Score is the user's long-term skill rating.

It should not be a simple average of Read Accuracy.

A simple average is weaker because:

- it becomes slow to move after many questions
- it does not account for question difficulty
- it rewards consistency less elegantly than a rating system
- it is less exciting as a progression mechanic

Instead, Read Score should move up or down after each official question based on how the user's Read Accuracy compares to other users on the same question.

## Starting Read Score

Every user starts with:

```text
starting_read_score = 1500
```

## Read Score Update Model

After each official question closes:

1. Calculate each user's Read Accuracy.
2. Rank all eligible users by Read Accuracy for that question.
3. Convert each user's rank into a percentile.
4. Adjust Read Score up or down based on percentile.

### Formula

```text
percentile = user's percentile rank for that question
k = rating_movement_factor
score_delta = round(k * ((percentile - 0.50) / 0.50))
new_read_score = old_read_score + score_delta
```

Where:

```text
percentile = 0.95 means the user beat 95% of people
percentile = 0.50 means the user performed at the median
percentile = 0.10 means the user beat 10% of people
```

This produces positive movement for above-median performance and negative movement for below-median performance.

## Example Score Movement

Assume:

```text
k = 16
```

| Daily Percentile | Score Change |
|---:|---:|
| Top 1% | +16 |
| Top 10% | +13 |
| Top 25% | +8 |
| Median | 0 |
| Bottom 25% | -8 |
| Bottom 10% | -13 |
| Bottom 1% | -16 |

This makes Read Score feel dynamic without allowing a single question to swing the user's long-term rating too aggressively.

## K Factor

Early scores should move more quickly. Established scores should move more gradually.

Suggested K factor:

| Official Questions Answered | K Factor |
|---:|---:|
| 1-10 | 32 |
| 11-50 | 24 |
| 51-150 | 16 |
| 151+ | 12 |

This allows new users to find their level quickly while making long-term scores more stable.

## Percentile Ranking

Percentile should be calculated against all eligible users for that specific question.

Lower prediction error means better performance.

Recommended tie handling:

```text
percentile = (users_below + 0.5 * users_equal) / total_eligible_users
```

Where:

- `users_below` means users with worse Read Accuracy
- `users_equal` means users with the same Read Accuracy
- `total_eligible_users` means all official participants eligible for scoring

## Question Eligibility

Only official questions should affect Read Score.

Recommended scoring eligibility rules:

- user answered during the official window
- user submitted both answer and prediction
- question has closed
- official result has been locked
- question has enough valid responses to be scored

The app may set a minimum response threshold before a question affects Read Score.

Example:

```text
minimum_scored_responses = 50
```

If a question does not meet the threshold, it can still show Read Accuracy, but it should be marked as not counted toward Read Score.

## Category Scores

Category scores should not be separate rating systems.

They should be average Read Accuracy by category.

### Formula

```text
category_read_accuracy = average(read_accuracy for official questions in that category)
```

Only include official scored questions.

Suggested display rule:

```text
minimum_category_questions = 3
```

Do not show a category in "You read these best" or "You misjudge these" until the user has answered enough questions in that category.

## Optional Category Smoothing

To avoid one lucky answer making a category look artificially strong, category scores can use simple Bayesian smoothing.

Example:

```text
prior_mean = 75
prior_weight = 3

smoothed_category_score =
  ((sum_of_category_read_accuracy) + (prior_mean * prior_weight))
  / (category_question_count + prior_weight)
```

This makes early category scores more conservative.

## Recommended Stored Fields

### User Question Result

```text
user_id
question_id
selected_option_id
predicted_share
actual_share_for_selected_option
prediction_error
read_accuracy
daily_percentile
score_delta
counted_toward_score
created_at
scored_at
```

### User Profile Stats

```text
user_id
read_score
official_questions_answered
read_score_percentile
current_streak
longest_streak
average_read_accuracy
last_scored_question_id
updated_at
```

### Category Stats

```text
user_id
category_id
category_question_count
average_read_accuracy
smoothed_category_score
last_updated_at
```

## Product Language

Recommended wording:

```text
Read Accuracy
Read Score
A good read.
This day counted toward your score.
Based on 142 reads.
You read Technology best.
You misjudge Sports.
```

Avoid making the score feel like a participation counter. The number of questions answered should increase confidence in the user's score, but should not directly increase the score.

## Summary

Read Accuracy is an absolute per-question measure:

```text
100 - absolute prediction error
```

Read Score is a long-term relative rating:

```text
starting score 1500
adjust up or down based on daily percentile performance
```

This keeps the app easy to understand while making long-term progression more competitive, stable, and meaningful.
