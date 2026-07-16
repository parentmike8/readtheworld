export const STARTING_READ_SCORE = 1500;
export const DEFAULT_MINIMUM_SCORED_RESPONSES = 50;
export const EASTERN_TIME_ZONE = "America/New_York";
const DAY_MS = 24 * 60 * 60 * 1000;

export type LeaderboardInput = {
  uid: string;
  displayName?: string;
  avatarColor?: string;
  readScore: number;
  officialQuestionsAnswered: number;
  currentStreak?: number;
};

export type LeaderboardRow = Required<LeaderboardInput> & {
  rank: number;
};

export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function calculateReadAccuracy(
  predictedShare: number,
  actualShare: number,
): number {
  return Math.round(clamp(100 - Math.abs(predictedShare - actualShare), 0, 100));
}

export function calculatePredictionBias(
  predictedShare: number,
  actualShare: number,
): number {
  return Math.round((predictedShare - actualShare) * 10) / 10;
}

export function averagePredictionBiasLabel(averageBias: number): "over" | "under" | "balanced" {
  if (averageBias >= 2) return "over";
  if (averageBias <= -2) return "under";
  return "balanced";
}

export function kFactor(officialQuestionsAnswered: number): number {
  if (officialQuestionsAnswered < 10) return 32;
  if (officialQuestionsAnswered < 50) return 24;
  if (officialQuestionsAnswered < 150) return 16;
  return 12;
}

export function scoreDeltaForPercentile(
  percentile: number,
  officialQuestionsAnswered: number,
): number {
  const k = kFactor(officialQuestionsAnswered);
  return Math.round(k * ((clamp(percentile, 0, 1) - 0.5) / 0.5));
}

export function percentileFromTieCounts(
  usersBelow: number,
  usersEqual: number,
  totalEligibleUsers: number,
): number {
  if (totalEligibleUsers <= 0) return 0;
  return clamp((usersBelow + 0.5 * usersEqual) / totalEligibleUsers, 0, 1);
}

export function dailyPercentilesByAccuracy(accuracies: number[]): Map<number, number> {
  const sorted = [...accuracies].sort((a, b) => a - b);
  const counts = new Map<number, number>();
  for (const accuracy of sorted) {
    counts.set(accuracy, (counts.get(accuracy) ?? 0) + 1);
  }

  const percentiles = new Map<number, number>();
  let usersBelow = 0;
  for (const accuracy of [...counts.keys()].sort((a, b) => a - b)) {
    const usersEqual = counts.get(accuracy) ?? 0;
    percentiles.set(
      accuracy,
      percentileFromTieCounts(usersBelow, usersEqual, accuracies.length),
    );
    usersBelow += usersEqual;
  }
  return percentiles;
}

export function smoothedCategoryScore(
  accuracySum: number,
  count: number,
  priorMean = 75,
  priorWeight = 3,
): number {
  return Math.round(
    ((accuracySum + priorMean * priorWeight) / (count + priorWeight)) * 10,
  ) / 10;
}

export function dailyKeyForEasternDate(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: EASTERN_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function dailyKeyDayNumber(dailyKey: string): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dailyKey);
  if (!match) {
    throw new Error(`Invalid daily key: ${dailyKey}`);
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new Error(`Invalid daily key: ${dailyKey}`);
  }
  return Math.floor(date.getTime() / DAY_MS);
}

export function nextStreakForDailyKey(
  previousDailyKey: string | null | undefined,
  currentDailyKey: string,
  currentStreak: number,
): number {
  if (!previousDailyKey) return 1;
  const dayDelta = dailyKeyDayNumber(currentDailyKey) - dailyKeyDayNumber(previousDailyKey);
  if (dayDelta === 0) return Math.max(1, currentStreak);
  if (dayDelta === 1) return Math.max(0, currentStreak) + 1;
  return 1;
}

export function rankedLeaderboardRows(
  users: LeaderboardInput[],
  limit = 100,
): LeaderboardRow[] {
  const ordered = [...users]
    .filter((user) => user.uid.length > 0)
    .sort((a, b) => {
      const scoreDelta = b.readScore - a.readScore;
      if (scoreDelta !== 0) return scoreDelta;
      const answerDelta = b.officialQuestionsAnswered - a.officialQuestionsAnswered;
      if (answerDelta !== 0) return answerDelta;
      return a.uid.localeCompare(b.uid);
    })
    .slice(0, Math.max(0, limit));

  let previousScore: number | null = null;
  let previousRank = 0;
  return ordered.map((user, index) => {
    const rank = previousScore === user.readScore ? previousRank : index + 1;
    previousScore = user.readScore;
    previousRank = rank;
    return {
      uid: user.uid,
      displayName: user.displayName?.trim() || "Reader",
      avatarColor: user.avatarColor?.trim() || "blue",
      readScore: Math.round(user.readScore),
      officialQuestionsAnswered: Math.max(0, Math.round(user.officialQuestionsAnswered)),
      currentStreak: Math.max(0, Math.round(user.currentStreak ?? 0)),
      rank,
    };
  });
}

/** Fields fanOutFriendProfile copies onto friends' docs. */
export function friendProfileChanged(
  existing: Record<string, unknown> | null | undefined,
  next: Pick<
    LeaderboardRow,
    "displayName" | "avatarColor" | "readScore" | "currentStreak" | "officialQuestionsAnswered"
  >,
): boolean {
  if (!existing) return true;
  return String(existing.displayName ?? "") !== next.displayName ||
    String(existing.avatarColor ?? "") !== next.avatarColor ||
    Number(existing.readScore) !== next.readScore ||
    Number(existing.currentStreak) !== next.currentStreak ||
    Number(existing.officialQuestionsAnswered) !== next.officialQuestionsAnswered;
}

/**
 * The hourly recompute rewrites only rows that actually moved; a missing
 * stored row always counts as changed.
 */
export function leaderboardRowChanged(
  existing: Record<string, unknown> | null | undefined,
  next: LeaderboardRow,
  nextReadScorePercentile: number,
): boolean {
  if (!existing) return true;
  return friendProfileChanged(existing, next) ||
    Number(existing.rank) !== next.rank ||
    Number(existing.readScorePercentile) !== nextReadScorePercentile;
}

export function readScorePercentileFromRank(
  rank: number,
  totalEligibleUsers: number,
): number {
  if (totalEligibleUsers <= 0 || rank <= 0) return 0;
  const percentile = 100 - (((rank - 0.5) / totalEligibleUsers) * 100);
  return Math.round(clamp(percentile, 0, 100) * 10) / 10;
}
