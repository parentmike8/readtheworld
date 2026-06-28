export type DailyOpenSkipReason =
  | "live-question-still-open"
  | "no-scheduled-question";

export type DailyOpenDecision = {
  openQuestionId: string | null;
  skipReason: DailyOpenSkipReason | null;
};

export function decideDailyOpen(
  remainingLiveQuestionIds: string[],
  scheduledQuestionIds: string[],
): DailyOpenDecision {
  if (remainingLiveQuestionIds.length > 0) {
    return {
      openQuestionId: null,
      skipReason: "live-question-still-open",
    };
  }

  const nextQuestionId = scheduledQuestionIds[0];
  if (!nextQuestionId) {
    return {
      openQuestionId: null,
      skipReason: "no-scheduled-question",
    };
  }

  return {
    openQuestionId: nextQuestionId,
    skipReason: null,
  };
}
