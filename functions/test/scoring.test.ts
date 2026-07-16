import { describe, expect, it } from "vitest";
import {
  averagePredictionBiasLabel,
  calculatePredictionBias,
  calculateReadAccuracy,
  dailyPercentilesByAccuracy,
  dailyKeyForEasternDate,
  friendProfileChanged,
  kFactor,
  leaderboardRowChanged,
  nextStreakForDailyKey,
  percentileFromTieCounts,
  rankedLeaderboardRows,
  readScorePercentileFromRank,
  scoreDeltaForPercentile,
  smoothedCategoryScore,
  type LeaderboardRow,
} from "../src/scoring";

describe("Read Accuracy", () => {
  it("scores absolute percentage-point error", () => {
    expect(calculateReadAccuracy(5, 16)).toBe(89);
    expect(calculateReadAccuracy(42, 35)).toBe(93);
  });

  it("clamps low scores at zero", () => {
    expect(calculateReadAccuracy(0, 150)).toBe(0);
  });
});

describe("Prediction bias", () => {
  it("keeps signed over and under estimates", () => {
    expect(calculatePredictionBias(72, 58)).toBe(14);
    expect(calculatePredictionBias(38, 51)).toBe(-13);
  });

  it("labels only meaningful aggregate lean", () => {
    expect(averagePredictionBiasLabel(2)).toBe("over");
    expect(averagePredictionBiasLabel(-2)).toBe("under");
    expect(averagePredictionBiasLabel(1.9)).toBe("balanced");
  });
});

describe("Read Score movement", () => {
  it("uses faster early K factors", () => {
    expect(kFactor(0)).toBe(32);
    expect(kFactor(10)).toBe(24);
    expect(kFactor(50)).toBe(16);
    expect(kFactor(150)).toBe(12);
  });

  it("moves up above median and down below median", () => {
    expect(scoreDeltaForPercentile(0.95, 50)).toBe(14);
    expect(scoreDeltaForPercentile(0.5, 50)).toBe(0);
    expect(scoreDeltaForPercentile(0.1, 50)).toBe(-13);
  });

  it("handles percentile ties by midpoint rank", () => {
    expect(percentileFromTieCounts(90, 10, 100)).toBe(0.95);
    const percentiles = dailyPercentilesByAccuracy([80, 90, 90, 100]);
    expect(percentiles.get(80)).toBe(0.125);
    expect(percentiles.get(90)).toBe(0.5);
    expect(percentiles.get(100)).toBe(0.875);
  });
});

describe("Category smoothing", () => {
  it("pulls early category scores toward the prior", () => {
    expect(smoothedCategoryScore(100, 1)).toBe(81.3);
    expect(smoothedCategoryScore(270, 3)).toBe(82.5);
  });
});

describe("Eastern daily windows", () => {
  it("uses the America/New_York calendar date at midnight boundaries", () => {
    expect(dailyKeyForEasternDate(new Date("2026-03-08T04:59:59.000Z"))).toBe(
      "2026-03-07",
    );
    expect(dailyKeyForEasternDate(new Date("2026-03-08T05:00:00.000Z"))).toBe(
      "2026-03-08",
    );
    expect(dailyKeyForEasternDate(new Date("2026-11-01T03:59:59.000Z"))).toBe(
      "2026-10-31",
    );
    expect(dailyKeyForEasternDate(new Date("2026-11-01T04:00:00.000Z"))).toBe(
      "2026-11-01",
    );
  });
});

describe("Streaks", () => {
  it("starts, continues, idempotently keeps, and resets daily streaks", () => {
    expect(nextStreakForDailyKey(null, "2026-06-20", 0)).toBe(1);
    expect(nextStreakForDailyKey("2026-06-20", "2026-06-21", 4)).toBe(5);
    expect(nextStreakForDailyKey("2026-06-21", "2026-06-21", 5)).toBe(5);
    expect(nextStreakForDailyKey("2026-06-21", "2026-06-23", 5)).toBe(1);
  });
});

describe("Leaderboards", () => {
  it("ranks by score, breaks display ordering by answer count, and preserves score ties", () => {
    const rows = rankedLeaderboardRows([
      { uid: "c", readScore: 1510, officialQuestionsAnswered: 4 },
      { uid: "a", displayName: "Ari", readScore: 1600, officialQuestionsAnswered: 2 },
      { uid: "b", displayName: "Bea", readScore: 1600, officialQuestionsAnswered: 7 },
      { uid: "d", displayName: "", readScore: 1400, officialQuestionsAnswered: 1 },
    ]);

    expect(rows.map((row) => row.uid)).toEqual(["b", "a", "c", "d"]);
    expect(rows.map((row) => row.rank)).toEqual([1, 1, 3, 4]);
    expect(rows[3].displayName).toBe("Reader");
  });

  it("honors limits and ignores blank users", () => {
    const rows = rankedLeaderboardRows([
      { uid: "", readScore: 2000, officialQuestionsAnswered: 99 },
      { uid: "a", readScore: 1501, officialQuestionsAnswered: 1 },
      { uid: "b", readScore: 1500, officialQuestionsAnswered: 1 },
    ], 1);

    expect(rows).toHaveLength(1);
    expect(rows[0].uid).toBe("a");
  });

  it("converts global rank into a top-percentile label source", () => {
    expect(readScorePercentileFromRank(1, 100)).toBe(99.5);
    expect(readScorePercentileFromRank(6, 100)).toBe(94.5);
    expect(readScorePercentileFromRank(100, 100)).toBe(0.5);
    expect(readScorePercentileFromRank(0, 100)).toBe(0);
  });
});

describe("Leaderboard changed-row diff", () => {
  const row: LeaderboardRow = {
    uid: "u1",
    displayName: "Ada",
    avatarColor: "blue",
    readScore: 1540,
    officialQuestionsAnswered: 12,
    currentStreak: 4,
    rank: 7,
  };
  const stored = {
    uid: "u1",
    displayName: "Ada",
    avatarColor: "blue",
    readScore: 1540,
    officialQuestionsAnswered: 12,
    currentStreak: 4,
    rank: 7,
    readScorePercentile: 82.5,
  };

  it("skips rows where nothing visible moved", () => {
    expect(leaderboardRowChanged(stored, row, 82.5)).toBe(false);
    expect(friendProfileChanged(stored, row)).toBe(false);
  });

  it("treats a missing stored row as changed", () => {
    expect(leaderboardRowChanged(null, row, 82.5)).toBe(true);
    expect(leaderboardRowChanged(undefined, row, 82.5)).toBe(true);
    expect(friendProfileChanged(null, row)).toBe(true);
  });

  it("detects each visible field change", () => {
    expect(leaderboardRowChanged(stored, { ...row, readScore: 1541 }, 82.5)).toBe(true);
    expect(leaderboardRowChanged(stored, { ...row, displayName: "Ada L" }, 82.5)).toBe(true);
    expect(leaderboardRowChanged(stored, { ...row, avatarColor: "green" }, 82.5)).toBe(true);
    expect(leaderboardRowChanged(stored, { ...row, currentStreak: 5 }, 82.5)).toBe(true);
    expect(leaderboardRowChanged(stored, { ...row, officialQuestionsAnswered: 13 }, 82.5)).toBe(true);
    expect(leaderboardRowChanged(stored, { ...row, rank: 6 }, 82.5)).toBe(true);
    expect(leaderboardRowChanged(stored, row, 82.4)).toBe(true);
  });

  it("ignores rank and percentile for friend-profile fan-out", () => {
    expect(friendProfileChanged(stored, { ...row, rank: 1 })).toBe(false);
    expect(friendProfileChanged(stored, { ...row, currentStreak: 5 })).toBe(true);
  });

  it("treats a partial stored row as changed", () => {
    const { readScorePercentile: _dropped, ...withoutPercentile } = stored;
    expect(leaderboardRowChanged(withoutPercentile, row, 82.5)).toBe(true);
  });
});
