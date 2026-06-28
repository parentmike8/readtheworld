export type QuestionVisibilityStatus = "draft" | "scheduled" | "live" | "closed";

export type RevealedResultState = {
  resultExists: boolean;
  questionStatus?: string | null;
};

export function resultIsRevealed(state: RevealedResultState): boolean {
  return state.resultExists && state.questionStatus === "closed";
}
