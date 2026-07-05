import type { BankShape, BankTier } from "./bank";
import {
  calculateReadAccuracy,
  clamp,
  dailyPercentilesByAccuracy,
  scoreDeltaForPercentile,
} from "./scoring";

export const WORLD_ROOM_ID = "world";
export const WORLD_PLAYER_GOAL = 5000;
export const ROOM_QUESTIONS_PER_DAY = 3;
export const CUSTOM_QUEUE_CAP_PER_MEMBER = 10;
export const ROOM_STARTING_SCORE = 1500;

export const ROOM_TIERS: BankTier[] = ["work-safe", "normal", "mature"];

/** Room colors from the v2 prototype (oklch strings the client maps 1:1). */
export const ROOM_COLOR_OPTIONS = [
  "oklch(0.50 0.07 155)",
  "oklch(0.55 0.105 47)",
  "oklch(0.50 0.10 256)",
  "oklch(0.55 0.14 300)",
  "oklch(0.52 0.12 200)",
  "#3A372F",
];

export class RoomValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RoomValidationError";
  }
}

export function normalizeRoomName(value: unknown): string {
  const name = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  if (name.length < 1 || name.length > 30) {
    throw new RoomValidationError("Room names must be 1-30 characters.");
  }
  return name;
}

export function normalizeRoomTier(value: unknown): BankTier {
  const tier = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (ROOM_TIERS.includes(tier as BankTier)) return tier as BankTier;
  throw new RoomValidationError("Tier must be work-safe, normal, or mature.");
}

export function normalizeRoomColor(value: unknown): string {
  const color = typeof value === "string" ? value.trim() : "";
  if (ROOM_COLOR_OPTIONS.includes(color)) return color;
  return ROOM_COLOR_OPTIONS[2];
}

export function normalizeRoomCats(value: unknown): string[] {
  const raw = Array.isArray(value) ? value : ["All"];
  const cats = raw
    .map((cat) => (typeof cat === "string" ? cat.trim() : ""))
    .filter((cat) => cat.length > 0 && cat.length <= 40);
  if (cats.length === 0 || cats.includes("All")) return ["All"];
  return [...new Set(cats)].slice(0, 8);
}

/**
 * Tier gating [Mike]: everyday (normal) includes work-safe, but After Dark
 * deliberately EXCLUDES work-safe — a table that picked the edgy game
 * shouldn't be dealt tame filler.
 */
export function tierAllowsQuestion(roomTier: BankTier, questionTier: BankTier): boolean {
  if (roomTier === "mature") return questionTier !== "work-safe";
  if (roomTier === "normal") return questionTier !== "mature";
  return questionTier === "work-safe";
}

export function catsAllowQuestion(roomCats: string[], questionTags: string[]): boolean {
  if (roomCats.length === 0 || roomCats.includes("All")) return true;
  return questionTags.some((tag) => roomCats.includes(tag));
}

/**
 * Dynamic custom-question injection [Mike]: deeper queues drain faster;
 * customs last when the queue is shallow. Always >=1 when anything is queued.
 */
export function customInjectionCount(queueDepth: number): number {
  if (queueDepth <= 0) return 0;
  if (queueDepth <= 4) return 1;
  if (queueDepth <= 9) return 2;
  return 3;
}

export function hashString(value: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

export type CandidateQuestion = {
  id: string;
  prompt: string;
  optA: string;
  optB: string;
  tags: string[];
  tier: BankTier;
  shape: BankShape;
  timesUsed: number;
};

export type DailySelectionInput = {
  roomId: string;
  dailyKey: string;
  roomTier: BankTier;
  roomCats: string[];
  candidates: CandidateQuestion[];
  usedQuestionIds: Set<string>;
  seenByMemberIds: Set<string>;
  dislikedByMemberIds: Set<string>;
  count: number;
};

/**
 * Deterministic daily pick: hard per-room no-repeat, prefer questions no
 * current member has seen anywhere, then least-used bank-wide, then a
 * date-salted hash for stable-but-shuffled ordering. Greedy shape variety —
 * avoid repeating a shape within the day until unavoidable.
 */
export function selectDailyQuestions(input: DailySelectionInput): CandidateQuestion[] {
  const eligible = input.candidates.filter((candidate) =>
    tierAllowsQuestion(input.roomTier, candidate.tier) &&
    catsAllowQuestion(input.roomCats, candidate.tags) &&
    !input.usedQuestionIds.has(candidate.id) &&
    !input.dislikedByMemberIds.has(candidate.id));

  const ordered = [...eligible].sort((a, b) => {
    const aSeen = input.seenByMemberIds.has(a.id) ? 1 : 0;
    const bSeen = input.seenByMemberIds.has(b.id) ? 1 : 0;
    if (aSeen !== bSeen) return aSeen - bSeen;
    if (a.timesUsed !== b.timesUsed) return a.timesUsed - b.timesUsed;
    const aHash = hashString(`${a.id}|${input.dailyKey}|${input.roomId}`);
    const bHash = hashString(`${b.id}|${input.dailyKey}|${input.roomId}`);
    if (aHash !== bHash) return aHash - bHash;
    return a.id.localeCompare(b.id);
  });

  const picked: CandidateQuestion[] = [];
  const remaining = [...ordered];
  while (picked.length < input.count && remaining.length > 0) {
    const usedShapes = new Set(picked.map((question) => question.shape));
    const index = remaining.findIndex((question) => !usedShapes.has(question.shape));
    const takeAt = index >= 0 ? index : 0;
    picked.push(remaining[takeAt]);
    remaining.splice(takeAt, 1);
  }
  return picked;
}

export type RoomMemberDayResult = {
  uid: string;
  /** Read accuracies for the member's predicted picks (0-100 each). */
  accuracies: number[];
  /** Lifetime predicted-question count BEFORE today (drives the K-factor). */
  questionsAnswered: number;
};

export type RoomMemberDayDelta = {
  uid: string;
  avgAccuracy: number;
  percentile: number;
  delta: number;
};

/**
 * Daily room scoring: rank members by average accuracy within the room, then
 * apply the existing Elo-style delta (K shrinks with lifetime answers so newer
 * players can catch up). Members with no predicted picks are excluded.
 */
export function roomDailyScoreDeltas(results: RoomMemberDayResult[]): RoomMemberDayDelta[] {
  const scored = results.filter((result) => result.accuracies.length > 0);
  if (scored.length === 0) return [];
  const averages = scored.map((result) => ({
    uid: result.uid,
    questionsAnswered: result.questionsAnswered,
    avgAccuracy: Math.round(
      (result.accuracies.reduce((sum, value) => sum + value, 0) /
        result.accuracies.length) * 10,
    ) / 10,
  }));
  if (averages.length === 1) {
    // Nothing to rank against — hold steady rather than punish/inflate.
    return [{ uid: averages[0].uid, avgAccuracy: averages[0].avgAccuracy, percentile: 0.5, delta: 0 }];
  }
  const percentiles = dailyPercentilesByAccuracy(averages.map((entry) => entry.avgAccuracy));
  return averages.map((entry) => {
    const percentile = percentiles.get(entry.avgAccuracy) ?? 0.5;
    return {
      uid: entry.uid,
      avgAccuracy: entry.avgAccuracy,
      percentile,
      delta: scoreDeltaForPercentile(percentile, entry.questionsAnswered),
    };
  });
}

export type WorldPredictorInput = {
  uid: string;
  side: "a" | "b";
  prediction: number;
  /** Lifetime world questions already scored for this reader (drives K). */
  worldQuestionsScored: number;
};

export type WorldQuestionScore = {
  uid: string;
  accuracy: number;
  percentile: number;
  delta: number;
};

export type WorldQuestionScoreResult = {
  /** Share of all responders (with a side) that picked option A, 0-100. */
  aPct: number;
  scores: WorldQuestionScore[];
};

/**
 * The World scores a single question globally when it crosses its answer
 * threshold: each reader's accuracy is their prediction vs the actual share of
 * everyone who agreed with their side (denominator = responders, not room
 * members [Mike]), then ranked into an Elo-style worldReadScore delta. Readers
 * who answered without a prediction still count toward the split but are not
 * scored.
 */
export function scoreWorldQuestion(input: {
  aCount: number;
  bCount: number;
  predictors: WorldPredictorInput[];
}): WorldQuestionScoreResult {
  const total = input.aCount + input.bCount;
  const aPct = total > 0 ? Math.round((input.aCount / total) * 100) : 0;
  const accuracies = input.predictors.map((predictor) => {
    const sameSide = predictor.side === "a" ? input.aCount : input.bCount;
    const actualShare = total > 0 ? Math.round((sameSide / total) * 100) : 0;
    return {
      uid: predictor.uid,
      questionsScored: predictor.worldQuestionsScored,
      accuracy: calculateReadAccuracy(predictor.prediction, actualShare),
    };
  });
  const percentiles = dailyPercentilesByAccuracy(
    accuracies.map((entry) => entry.accuracy),
  );
  const scores = accuracies.map((entry) => {
    const percentile = percentiles.get(entry.accuracy) ?? 0.5;
    return {
      uid: entry.uid,
      accuracy: entry.accuracy,
      percentile,
      delta: scoreDeltaForPercentile(percentile, entry.questionsScored),
    };
  });
  return { aPct, scores };
}

export function normalizeCustomQuestionText(value: unknown): string {
  const text = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  if (text.length < 8 || text.length > 140) {
    throw new RoomValidationError("Custom questions must be 8-140 characters.");
  }
  return text;
}

export function normalizeCustomOption(value: unknown, fallback: string): string {
  const label = typeof value === "string" ? value.trim() : "";
  if (!label) return fallback;
  if (label.length > 24) {
    throw new RoomValidationError("Custom option labels must be 24 characters or fewer.");
  }
  return label;
}

export function normalizePrediction(value: unknown): number | null {
  if (value == null) return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new RoomValidationError("Predictions must be a number from 0 to 100.");
  }
  return Math.round(clamp(parsed, 0, 100));
}
