import { dailyKeyForEasternDate } from "./scoring";
import { QuestionValidationError } from "./questions";

export type SeedQuestion = {
  slug: string;
  category: string;
  prompt: string;
  options: Array<{ id: string; label: string }>;
};

export type ScheduledSeedQuestion = SeedQuestion & {
  id: string;
  type: "binary" | "choice";
  status: "live" | "scheduled";
  dailyKey: string;
  publishAt: Date;
  closeAt: Date;
};

const DAY_MS = 24 * 60 * 60 * 1000;
const EASTERN_TIME_ZONE = "America/New_York";
const DAILY_KEY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

export const seedQuestions: SeedQuestion[] = [
  {
    slug: "philosophy-death-date",
    category: "PHILOSOPHY",
    prompt: "Would you want to know the exact date you'll die?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "technology-ai-labels",
    category: "TECHNOLOGY",
    prompt: "Should AI-generated content always be labelled?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "money-four-day-week",
    category: "MONEY",
    prompt: "Would you take a 20% pay cut for a four-day work week?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "global-events-mars",
    category: "GLOBAL EVENTS",
    prompt: "Will humans set foot on Mars before 2040?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "culture-phones-dinner",
    category: "CULTURE",
    prompt: "Is it rude to keep your phone on the table during dinner?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "business-work-week",
    category: "BUSINESS",
    prompt: "Will the four-day work week be the norm by 2035?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "choice-world-language",
    category: "GLOBAL EVENTS",
    prompt: "Which language will be most important globally in 2100?",
    options: [
      { id: "english", label: "English" },
      { id: "mandarin", label: "Mandarin" },
      { id: "spanish", label: "Spanish" },
      { id: "hindi", label: "Hindi" },
    ],
  },
];

export function buildSeedQuestionSchedule({
  startDailyKey,
  now = new Date(),
}: {
  startDailyKey?: string | null;
  now?: Date;
} = {}): ScheduledSeedQuestion[] {
  const firstDailyKey = startDailyKey ? validateDailyKey(startDailyKey) : dailyKeyForEasternDate(now);
  return seedQuestions.map((question, index) => {
    const dailyKey = addDaysToDailyKey(firstDailyKey, index);
    const publishAt = easternMidnightUtcForDailyKey(dailyKey);
    const closeAt = easternMidnightUtcForDailyKey(addDaysToDailyKey(dailyKey, 1));
    return {
      ...question,
      id: `${dailyKey}-${question.slug}`,
      type: question.options.length === 2 ? "binary" : "choice",
      status: index === 0 ? "live" : "scheduled",
      dailyKey,
      publishAt,
      closeAt,
    };
  });
}

export function addDaysToDailyKey(dailyKey: string, days: number): string {
  const { year, month, day } = parseDailyKey(dailyKey);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return [
    String(date.getUTCFullYear()).padStart(4, "0"),
    String(date.getUTCMonth() + 1).padStart(2, "0"),
    String(date.getUTCDate()).padStart(2, "0"),
  ].join("-");
}

export function easternMidnightUtcForDailyKey(dailyKey: string): Date {
  const { year, month, day } = parseDailyKey(dailyKey);
  const localMidnightAsUtc = Date.UTC(year, month - 1, day, 0, 0, 0);
  const offsetMinutes = timeZoneOffsetMinutes(
    new Date(Date.UTC(year, month - 1, day, 5, 0, 0)),
    EASTERN_TIME_ZONE,
  );
  return new Date(localMidnightAsUtc - offsetMinutes * 60 * 1000);
}

function validateDailyKey(dailyKey: string): string {
  parseDailyKey(dailyKey);
  return dailyKey;
}

function parseDailyKey(dailyKey: string): { year: number; month: number; day: number } {
  const match = DAILY_KEY_PATTERN.exec(dailyKey);
  if (!match) {
    throw new QuestionValidationError("Seed startDailyKey must use YYYY-MM-DD format.");
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
    throw new QuestionValidationError("Seed startDailyKey must be a valid calendar date.");
  }
  return { year, month, day };
}

function timeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const localAsUtc = Date.UTC(
    Number(values.year),
    Number(values.month) - 1,
    Number(values.day),
    Number(values.hour),
    Number(values.minute),
    Number(values.second),
  );
  return (localAsUtc - date.getTime()) / (60 * 1000);
}
