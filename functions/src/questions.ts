export type QuestionStatus = "draft" | "scheduled" | "live" | "closed";

export type NormalizedQuestionOption = {
  id: string;
  label: string;
};

export type QuestionScheduleInput = {
  status: QuestionStatus;
  dailyKey: string | null;
  publishAt: Date | null;
  closeAt: Date | null;
};

const QUESTION_STATUSES: QuestionStatus[] = ["draft", "scheduled", "live", "closed"];
const OPTION_ID_PATTERN = /^[a-z0-9][a-z0-9_-]{0,39}$/;
const DAILY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export class QuestionValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QuestionValidationError";
  }
}

export function normalizeQuestionStatus(value: unknown): QuestionStatus {
  const status = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (QUESTION_STATUSES.includes(status as QuestionStatus)) {
    return status as QuestionStatus;
  }
  throw new QuestionValidationError("Status must be draft, scheduled, live, or closed.");
}

export function normalizeQuestionOptions(value: unknown): NormalizedQuestionOption[] {
  if (!Array.isArray(value) || value.length < 2) {
    throw new QuestionValidationError("At least two options are required.");
  }

  const seenIds = new Set<string>();
  return value.map((option, index) => {
    if (!option || typeof option !== "object") {
      throw new QuestionValidationError(`Option ${index + 1} is invalid.`);
    }
    const record = option as Record<string, unknown>;
    const id = normalizeOptionId(record.id);
    const label = typeof record.label === "string" ? record.label.trim() : "";
    if (!id || !label) {
      throw new QuestionValidationError(`Option ${index + 1} needs an id and label.`);
    }
    if (!OPTION_ID_PATTERN.test(id)) {
      throw new QuestionValidationError(
        "Option ids may use lowercase letters, numbers, underscores, and hyphens.",
      );
    }
    if (label.length > 80) {
      throw new QuestionValidationError("Option labels must be 80 characters or fewer.");
    }
    if (seenIds.has(id)) {
      throw new QuestionValidationError(`Option id "${id}" is duplicated.`);
    }
    seenIds.add(id);
    return { id, label };
  });
}

export function normalizeDailyKey(value: unknown): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new QuestionValidationError("Daily key must be a YYYY-MM-DD string.");
  }
  const dailyKey = value.trim();
  if (!DAILY_KEY_PATTERN.test(dailyKey)) {
    throw new QuestionValidationError("Daily key must use YYYY-MM-DD format.");
  }
  return dailyKey;
}

export function parseQuestionDate(value: unknown, field: string): Date | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new QuestionValidationError(`${field} must be an ISO date string.`);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new QuestionValidationError(`${field} must be a valid date.`);
  }
  return date;
}

export function validateQuestionSchedule(input: QuestionScheduleInput): void {
  const scheduled = input.status !== "draft";
  if (scheduled && !input.dailyKey) {
    throw new QuestionValidationError("Daily key is required before a question is scheduled.");
  }
  if (scheduled && (!input.publishAt || !input.closeAt)) {
    throw new QuestionValidationError("Publish and close dates are required before scheduling.");
  }
  if (input.publishAt && input.closeAt && input.closeAt.getTime() <= input.publishAt.getTime()) {
    throw new QuestionValidationError("Close date must be after publish date.");
  }
}

function normalizeOptionId(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().toLowerCase().replace(/\s+/g, "-");
}
