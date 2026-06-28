import { STARTING_READ_SCORE } from "./scoring";

export type UserProgressDefaults = {
  readScore: number;
  officialQuestionsAnswered: number;
  currentStreak: number;
  longestStreak: number;
};

export function missingUserProgressDefaults(data?: Record<string, unknown> | null): Partial<UserProgressDefaults> {
  const defaults: Partial<UserProgressDefaults> = {};
  if (typeof data?.readScore !== "number") {
    defaults.readScore = STARTING_READ_SCORE;
  }
  if (typeof data?.officialQuestionsAnswered !== "number") {
    defaults.officialQuestionsAnswered = 0;
  }
  if (typeof data?.currentStreak !== "number") {
    defaults.currentStreak = 0;
  }
  if (typeof data?.longestStreak !== "number") {
    defaults.longestStreak = 0;
  }
  return defaults;
}
