export const PRACTICE_ANSWER_SOURCES = [
  "history-replay",
  "party-replay",
  "archive-replay",
  "peek",
] as const;

export type PracticeAnswerSource = (typeof PRACTICE_ANSWER_SOURCES)[number];

export function isPracticeAnswerSource(value: unknown): value is PracticeAnswerSource {
  return typeof value === "string" &&
    PRACTICE_ANSWER_SOURCES.includes(value as PracticeAnswerSource);
}
