import { describe, expect, it } from "vitest";
import type { CandidateQuestion } from "../src/rooms";
import {
  RoomValidationError,
  WORLD_REVEAL_CLAIM_STALE_MS,
  catsAllowQuestion,
  customInjectionCount,
  hasClearlyObjectionableContent,
  mergeLockedPicks,
  normalizeCustomOption,
  normalizeCustomQuestionText,
  normalizePrediction,
  normalizeRoomCats,
  normalizeRoomName,
  normalizeRoomTier,
  predictedPickCount,
  questionsAnsweredBeforeDay,
  roomDailyScoreDeltas,
  roomRolloverPlan,
  scoreWorldQuestion,
  selectDailyQuestions,
  submittedQuestionDisposition,
  tierAllowsQuestion,
  worldRevealClaimDecision,
  worldRevealCandidateQids,
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

  it("screens only clearly objectionable custom-question text", () => {
    expect(hasClearlyObjectionableContent("This deadline is killing me. Swear words okay?"))
      .toBe(false);
    expect(hasClearlyObjectionableContent("Should politicians be allowed to lie?"))
      .toBe(false);
    expect(hasClearlyObjectionableContent("I will kill you tomorrow"))
      .toBe(true);
    expect(hasClearlyObjectionableContent("K1ll yourself"))
      .toBe(true);
    expect(hasClearlyObjectionableContent("underage porn"))
      .toBe(true);
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

describe("roomRolloverPlan", () => {
  it("always gives The World a fresh daily set without closing threshold-based days", () => {
    expect(roomRolloverPlan("world")).toEqual({
      closePreviousDays: false,
      ensureToday: true,
    });
  });

  it("closes prior days and creates today for private rooms", () => {
    expect(roomRolloverPlan("studio")).toEqual({
      closePreviousDays: true,
      ensureToday: true,
    });
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

describe("mergeLockedPicks", () => {
  const pick = (qid: string, side: "a" | "b" = "a", prediction: number | null = 50) =>
    ({ qid, side, prediction });

  it("replaces unrevealed picks and counts a first-time answer", () => {
    const merged = mergeLockedPicks({
      existingPicks: [],
      newPicks: [pick("q1"), pick("q2")],
      revealedQids: new Set<string>(),
    });
    expect(merged.picks).toEqual([pick("q1"), pick("q2")]);
    expect(merged.incrementQids).toEqual(["q1", "q2"]);
    expect(merged.decrementQids).toEqual([]);
  });

  it("preserves revealed picks untouched on a re-lock", () => {
    const revealedPick = pick("q1", "b", 80);
    const merged = mergeLockedPicks({
      existingPicks: [revealedPick, pick("q2", "a", 40)],
      newPicks: [pick("q2", "b", 60), pick("q3")],
      revealedQids: new Set(["q1"]),
    });
    // q1 stays exactly as stored; q2 is replaced; q3 is added.
    expect(merged.picks).toEqual([revealedPick, pick("q2", "b", 60), pick("q3")]);
    expect(merged.incrementQids).toEqual(["q3"]);
    expect(merged.decrementQids).toEqual([]);
  });

  it("never decrements answer counts for revealed questions", () => {
    const merged = mergeLockedPicks({
      existingPicks: [pick("q1"), pick("q2")],
      newPicks: [pick("q3")],
      revealedQids: new Set(["q1"]),
    });
    // q1 already revealed: kept, not decremented. q2 was replaceable and
    // dropped: decremented.
    expect(merged.picks).toEqual([pick("q1"), pick("q3")]);
    expect(merged.incrementQids).toEqual(["q3"]);
    expect(merged.decrementQids).toEqual(["q2"]);
  });

  it("ignores a new pick that targets a revealed question", () => {
    const storedPick = pick("q1", "a", 30);
    const merged = mergeLockedPicks({
      existingPicks: [storedPick],
      newPicks: [pick("q1", "b", 90), pick("q2")],
      revealedQids: new Set(["q1"]),
    });
    expect(merged.picks).toEqual([storedPick, pick("q2")]);
    expect(merged.incrementQids).toEqual(["q2"]);
    expect(merged.decrementQids).toEqual([]);
  });

  it("supports legacy stored pick shapes without touching them", () => {
    const legacy = { qid: "q1", side: "a", predictedShare: 70 };
    const merged = mergeLockedPicks({
      existingPicks: [legacy],
      newPicks: [pick("q2")],
      revealedQids: new Set(["q1"]),
    });
    expect(merged.picks[0]).toBe(legacy);
  });
});

describe("worldRevealClaimDecision", () => {
  const base = {
    qid: "q1",
    revealedQids: [] as string[],
    revealingQids: [] as string[],
    claimedAtMs: null as number | null,
    nowMs: 1_000_000,
  };

  it("claims fresh when the qid is unclaimed", () => {
    expect(worldRevealClaimDecision(base)).toBe("fresh-claim");
  });

  it("treats revealedQids as done, even alongside a leftover claim", () => {
    expect(worldRevealClaimDecision({
      ...base,
      revealedQids: ["q1"],
      revealingQids: ["q1"],
      claimedAtMs: 0,
    })).toBe("done");
  });

  it("backs off while another invocation holds a fresh claim", () => {
    expect(worldRevealClaimDecision({
      ...base,
      revealingQids: ["q1"],
      claimedAtMs: base.nowMs - WORLD_REVEAL_CLAIM_STALE_MS + 1,
    })).toBe("in-progress");
  });

  it("re-claims a stale claim (a crashed reveal)", () => {
    expect(worldRevealClaimDecision({
      ...base,
      revealingQids: ["q1"],
      claimedAtMs: base.nowMs - WORLD_REVEAL_CLAIM_STALE_MS,
    })).toBe("stale-claim");
  });

  it("re-claims a claim without a readable timestamp", () => {
    expect(worldRevealClaimDecision({
      ...base,
      revealingQids: ["q1"],
      claimedAtMs: null,
    })).toBe("stale-claim");
  });

  it("only reacts to claims for the same qid", () => {
    expect(worldRevealClaimDecision({
      ...base,
      revealingQids: ["q2"],
      revealedQids: ["q3"],
    })).toBe("fresh-claim");
  });
});

describe("worldRevealCandidateQids", () => {
  const questions = [
    { qid: "ready", threshold: 5 },
    { qid: "waiting", threshold: 10 },
    { qid: "default-threshold" },
    { qid: "pulled", threshold: 1, pulled: true },
    { qid: "revealed", threshold: 1 },
  ];

  it("returns every unrevealed question at its answer threshold", () => {
    expect(worldRevealCandidateQids({
      questions,
      answerCounts: {
        ready: 5,
        waiting: 9,
        "default-threshold": 3,
        pulled: 20,
        revealed: 20,
      },
      revealedQids: new Set(["revealed"]),
      defaultThreshold: 3,
    })).toEqual(["ready", "default-threshold"]);
  });

  it("keeps claimed questions discoverable for stale-claim recovery", () => {
    expect(worldRevealCandidateQids({
      questions: [{ qid: "claimed", threshold: 2 }],
      answerCounts: { claimed: 2 },
      revealedQids: new Set(),
    })).toEqual(["claimed"]);
  });
});

describe("close-day K-factor adjustment", () => {
  it("subtracts today's predicted picks back out of the lifetime count", () => {
    expect(questionsAnsweredBeforeDay(12, 3)).toBe(9);
  });

  it("never goes below zero", () => {
    expect(questionsAnsweredBeforeDay(2, 3)).toBe(0);
    expect(questionsAnsweredBeforeDay(0, 0)).toBe(0);
  });

  it("ignores a negative pick count", () => {
    expect(questionsAnsweredBeforeDay(5, -2)).toBe(5);
  });

  it("counts picks with predictions, including legacy predictedShare", () => {
    expect(predictedPickCount([
      { qid: "q1", side: "a", prediction: 60 },
      { qid: "q2", side: "b", prediction: null },
      { qid: "q3", side: "a", predictedShare: 40 },
      { qid: "q4", side: "b" },
    ])).toBe(2);
  });
});

describe("submittedQuestionDisposition", () => {
  const dayQids = new Set(["active", "pulled", "revealed"]);
  const activeQids = new Set(["active"]);

  it("accepts a question that is still active", () => {
    expect(submittedQuestionDisposition("active", dayQids, activeQids)).toBe("active");
  });

  it("distinguishes a mid-round pull or reveal from a stale question set", () => {
    expect(submittedQuestionDisposition("pulled", dayQids, activeQids)).toBe("inactive");
    expect(submittedQuestionDisposition("revealed", dayQids, activeQids)).toBe("inactive");
    expect(submittedQuestionDisposition("yesterday", dayQids, activeQids)).toBe("unknown");
  });
});
