import { describe, expect, it } from "vitest";
import type { CandidateQuestion } from "../src/rooms";
import {
  RoomValidationError,
  catsAllowQuestion,
  customInjectionCount,
  normalizeCustomOption,
  normalizeCustomQuestionText,
  normalizePrediction,
  normalizeRoomCats,
  normalizeRoomName,
  normalizeRoomTier,
  roomDailyScoreDeltas,
  scoreWorldQuestion,
  selectDailyQuestions,
  tierAllowsQuestion,
} from "../src/rooms";

function candidate(overrides: Partial<CandidateQuestion> & { id: string }): CandidateQuestion {
  return {
    prompt: `Prompt ${overrides.id}`,
    optA: "Yes",
    optB: "No",
    tags: ["Social"],
    tier: "normal",
    shape: "TASTE",
    timesUsed: 0,
    ...overrides,
  };
}

describe("room normalization", () => {
  it("validates names, tiers, cats", () => {
    expect(normalizeRoomName("  The   Studio ")).toBe("The Studio");
    expect(() => normalizeRoomName("")).toThrow(RoomValidationError);
    expect(normalizeRoomTier("MATURE")).toBe("mature");
    expect(() => normalizeRoomTier("spicy")).toThrow(RoomValidationError);
    expect(normalizeRoomCats(["All", "Social"])).toEqual(["All"]);
    expect(normalizeRoomCats(["Social", "Ethics", "Social"])).toEqual(["Social", "Ethics"]);
    expect(normalizeRoomCats(undefined)).toEqual(["All"]);
  });

  it("validates custom questions and predictions", () => {
    expect(normalizeCustomQuestionText("  Should we do a  team offsite? "))
      .toBe("Should we do a team offsite?");
    expect(() => normalizeCustomQuestionText("Hey?")).toThrow(RoomValidationError);
    expect(normalizeCustomOption("", "Yes")).toBe("Yes");
    expect(normalizePrediction(62.4)).toBe(62);
    expect(normalizePrediction(null)).toBeNull();
    expect(normalizePrediction(140)).toBe(100);
    expect(() => normalizePrediction("lots")).toThrow(RoomValidationError);
  });
});

describe("tier and category gates", () => {
  it("everyday includes work-safe; After Dark drops it", () => {
    expect(tierAllowsQuestion("work-safe", "work-safe")).toBe(true);
    expect(tierAllowsQuestion("work-safe", "normal")).toBe(false);
    expect(tierAllowsQuestion("normal", "work-safe")).toBe(true);
    expect(tierAllowsQuestion("normal", "mature")).toBe(false);
    expect(tierAllowsQuestion("mature", "mature")).toBe(true);
    expect(tierAllowsQuestion("mature", "normal")).toBe(true);
    // The edgy game should never be diluted with tame filler.
    expect(tierAllowsQuestion("mature", "work-safe")).toBe(false);
  });

  it("cats gate by tag intersection with All bypass", () => {
    expect(catsAllowQuestion(["All"], ["Anything"])).toBe(true);
    expect(catsAllowQuestion(["Social"], ["Ethics", "Social"])).toBe(true);
    expect(catsAllowQuestion(["Social"], ["Ethics"])).toBe(false);
  });
});

describe("customInjectionCount", () => {
  it("scales with queue depth per product rule", () => {
    expect(customInjectionCount(0)).toBe(0);
    expect(customInjectionCount(1)).toBe(1);
    expect(customInjectionCount(4)).toBe(1);
    expect(customInjectionCount(5)).toBe(2);
    expect(customInjectionCount(9)).toBe(2);
    expect(customInjectionCount(10)).toBe(3);
    expect(customInjectionCount(25)).toBe(3);
  });
});

describe("selectDailyQuestions", () => {
  const base = {
    roomId: "studio",
    dailyKey: "2026-07-01",
    roomTier: "normal" as const,
    roomCats: ["All"],
    usedQuestionIds: new Set<string>(),
    seenByMemberIds: new Set<string>(),
    dislikedByMemberIds: new Set<string>(),
    count: 3,
  };

  it("never repeats a question the room has used", () => {
    const candidates = [
      candidate({ id: "a" }),
      candidate({ id: "b" }),
      candidate({ id: "c" }),
      candidate({ id: "d" }),
    ];
    const picked = selectDailyQuestions({
      ...base,
      candidates,
      usedQuestionIds: new Set(["a", "b"]),
    });
    expect(picked.map((question) => question.id).sort()).toEqual(["c", "d"]);
  });

  it("filters by tier and category", () => {
    const candidates = [
      candidate({ id: "mature", tier: "mature" }),
      candidate({ id: "offcat", tags: ["Money"] }),
      candidate({ id: "ok", tags: ["Social"] }),
    ];
    const picked = selectDailyQuestions({ ...base, roomCats: ["Social"], candidates });
    expect(picked.map((question) => question.id)).toEqual(["ok"]);
  });

  it("excludes questions disliked by any current room member", () => {
    const candidates = [
      candidate({ id: "liked-enough" }),
      candidate({ id: "member-disliked", timesUsed: 0 }),
      candidate({ id: "fine", shape: "GREY" }),
    ];
    const picked = selectDailyQuestions({
      ...base,
      candidates,
      dislikedByMemberIds: new Set(["member-disliked"]),
    });
    expect(picked.map((question) => question.id)).not.toContain("member-disliked");
    expect(picked.map((question) => question.id).sort()).toEqual(["fine", "liked-enough"]);
  });

  it("prefers questions unseen by members, then least used", () => {
    const candidates = [
      candidate({ id: "seen-fresh", timesUsed: 0 }),
      candidate({ id: "unseen-worn", timesUsed: 9, shape: "GREY" }),
      candidate({ id: "unseen-fresh", timesUsed: 1, shape: "TRADE" }),
    ];
    const picked = selectDailyQuestions({
      ...base,
      count: 2,
      candidates,
      seenByMemberIds: new Set(["seen-fresh"]),
    });
    expect(picked.map((question) => question.id)).toEqual(["unseen-fresh", "unseen-worn"]);
  });

  it("mixes shapes when possible and is deterministic", () => {
    const candidates = [
      candidate({ id: "t1", shape: "TASTE" }),
      candidate({ id: "t2", shape: "TASTE" }),
      candidate({ id: "g1", shape: "GREY" }),
      candidate({ id: "n1", shape: "NORM" }),
    ];
    const first = selectDailyQuestions({ ...base, candidates });
    const second = selectDailyQuestions({ ...base, candidates });
    expect(first).toEqual(second);
    expect(new Set(first.map((question) => question.shape)).size).toBe(3);
  });

  it("allows shape repeats only when unavoidable", () => {
    const candidates = [
      candidate({ id: "t1", shape: "TASTE" }),
      candidate({ id: "t2", shape: "TASTE" }),
      candidate({ id: "t3", shape: "TASTE" }),
    ];
    const picked = selectDailyQuestions({ ...base, candidates });
    expect(picked).toHaveLength(3);
  });

  it("varies ordering across days via the date-salted hash", () => {
    const candidates = Array.from({ length: 12 }, (_, i) =>
      candidate({ id: `q${i}` }));
    const day1 = selectDailyQuestions({ ...base, candidates });
    const day2 = selectDailyQuestions({ ...base, dailyKey: "2026-07-02", candidates });
    expect(day1.map((question) => question.id))
      .not.toEqual(day2.map((question) => question.id));
  });
});

describe("roomDailyScoreDeltas", () => {
  it("returns empty when no one predicted", () => {
    expect(roomDailyScoreDeltas([{ uid: "a", accuracies: [], questionsAnswered: 0 }]))
      .toEqual([]);
  });

  it("holds a lone scorer steady", () => {
    const deltas = roomDailyScoreDeltas([
      { uid: "a", accuracies: [90, 80, 70], questionsAnswered: 3 },
    ]);
    expect(deltas).toEqual([{ uid: "a", avgAccuracy: 80, percentile: 0.5, delta: 0 }]);
  });

  it("ranks within the room and pays winners", () => {
    const deltas = roomDailyScoreDeltas([
      { uid: "sharp", accuracies: [95, 90, 92], questionsAnswered: 200 },
      { uid: "mid", accuracies: [80, 75, 82], questionsAnswered: 20 },
      { uid: "new", accuracies: [60, 55, 58], questionsAnswered: 2 },
    ]);
    const byUid = Object.fromEntries(deltas.map((delta) => [delta.uid, delta]));
    expect(byUid.sharp.delta).toBeGreaterThan(0);
    expect(byUid.new.delta).toBeLessThan(0);
    // Veteran K (12) caps the winner's gain below a newcomer's max swing (32).
    expect(byUid.sharp.delta).toBeLessThanOrEqual(12);
    expect(byUid.new.delta).toBeGreaterThanOrEqual(-32);
  });

  it("gives newcomers bigger swings than veterans at the same rank distance", () => {
    const deltas = roomDailyScoreDeltas([
      { uid: "vet", accuracies: [90], questionsAnswered: 500 },
      { uid: "newbie", accuracies: [95], questionsAnswered: 1 },
      { uid: "mid", accuracies: [70], questionsAnswered: 60 },
    ]);
    const byUid = Object.fromEntries(deltas.map((delta) => [delta.uid, delta]));
    expect(Math.abs(byUid.newbie.delta)).toBeGreaterThan(Math.abs(byUid.vet.delta));
  });
});

describe("scoreWorldQuestion", () => {
  it("measures accuracy against the responder split (denominator = responders)", () => {
    // 6 of 8 responders picked A -> actual A share is 75%.
    const result = scoreWorldQuestion({
      aCount: 6,
      bCount: 2,
      predictors: [
        { uid: "spot-on", side: "a", prediction: 75, worldQuestionsScored: 0 },
        { uid: "way-off", side: "a", prediction: 20, worldQuestionsScored: 0 },
      ],
    });
    expect(result.aPct).toBe(75);
    const byUid = Object.fromEntries(result.scores.map((score) => [score.uid, score]));
    expect(byUid["spot-on"].accuracy).toBe(100);
    expect(byUid["way-off"].accuracy).toBe(45); // 100 - |20 - 75|
    // Reading the crowd better than the field earns a positive delta.
    expect(byUid["spot-on"].delta).toBeGreaterThan(0);
    expect(byUid["way-off"].delta).toBeLessThan(0);
  });

  it("scores B-side predictions against the B share", () => {
    const result = scoreWorldQuestion({
      aCount: 3,
      bCount: 1,
      predictors: [
        { uid: "b-reader", side: "b", prediction: 25, worldQuestionsScored: 0 },
      ],
    });
    // B share is 1/4 = 25%; a lone scorer holds steady (percentile 0.5).
    expect(result.scores[0].accuracy).toBe(100);
    expect(result.scores[0].delta).toBe(0);
  });

  it("counts non-predicting responders toward the split but not the scores", () => {
    const result = scoreWorldQuestion({
      aCount: 10,
      bCount: 10,
      predictors: [
        { uid: "only-predictor", side: "a", prediction: 50, worldQuestionsScored: 0 },
      ],
    });
    expect(result.aPct).toBe(50);
    expect(result.scores).toHaveLength(1);
  });
});
