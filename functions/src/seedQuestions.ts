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

export type ProductionSeedQuestion = SeedQuestion & {
  id: string;
  type: "binary" | "choice";
  status: "closed" | "live" | "scheduled";
  dailyKey: string;
  publishAt: Date;
  closeAt: Date;
  result?: SeedQuestionResult;
};

export type SeedQuestionResult = {
  closedAt: Date;
  totalAnswers: number;
  optionCounts: Record<string, number>;
  optionPcts: Record<string, number>;
  countedTowardScore: boolean;
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
  {
    slug: "science-fusion-grid",
    category: "SCIENCE",
    prompt: "Will fusion power reach the electrical grid within 20 years?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "relationships-location-sharing",
    category: "RELATIONSHIPS",
    prompt: "Should couples share their phone location with each other?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "sports-ai-referees",
    category: "SPORTS",
    prompt: "Should major sports use AI to overrule referee mistakes?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "politics-voting-online",
    category: "POLITICS",
    prompt: "Should national elections allow secure online voting?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "culture-hot-dog-sandwich",
    category: "CULTURE",
    prompt: "Is a hot dog a sandwich?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "technology-phone-free-schools",
    category: "TECHNOLOGY",
    prompt: "Should schools ban phones for the entire school day?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "money-cashless-society",
    category: "MONEY",
    prompt: "Will cash mostly disappear from daily life by 2035?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "business-office-mandates",
    category: "BUSINESS",
    prompt: "Do companies get better work when employees are in-office three days a week?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "science-lab-grown-meat",
    category: "SCIENCE",
    prompt: "Would you eat lab-grown meat if it tasted the same as regular meat?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "philosophy-perfect-memory",
    category: "PHILOSOPHY",
    prompt: "Would a perfect memory make life better?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "global-events-space-tourism",
    category: "GLOBAL EVENTS",
    prompt: "Will space tourism be normal for wealthy travelers within 25 years?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "choice-next-device",
    category: "TECHNOLOGY",
    prompt: "Which device will feel most essential ten years from now?",
    options: [
      { id: "phone", label: "Phone" },
      { id: "glasses", label: "Glasses" },
      { id: "watch", label: "Watch" },
      { id: "earbuds", label: "Earbuds" },
    ],
  },
  {
    slug: "culture-spoilers",
    category: "CULTURE",
    prompt: "Is it fair to discuss movie spoilers one week after release?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "relationships-dating-apps",
    category: "RELATIONSHIPS",
    prompt: "Have dating apps made dating better overall?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "sports-olympics-permanent-city",
    category: "SPORTS",
    prompt: "Should the Olympics have one permanent host city?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "politics-term-limits",
    category: "POLITICS",
    prompt: "Should elected officials have stricter term limits?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "science-gene-editing",
    category: "SCIENCE",
    prompt: "Should parents be allowed to edit embryos to prevent serious disease?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "money-home-ownership",
    category: "MONEY",
    prompt: "Will home ownership still be a realistic goal for most young adults?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "business-ai-managers",
    category: "BUSINESS",
    prompt: "Would you accept performance feedback from an AI manager?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "choice-trust-news",
    category: "CULTURE",
    prompt: "Where do you trust breaking news most?",
    options: [
      { id: "newspapers", label: "Newspapers" },
      { id: "tv", label: "TV" },
      { id: "social", label: "Social media" },
      { id: "friends", label: "Friends" },
    ],
  },
  {
    slug: "technology-self-driving",
    category: "TECHNOLOGY",
    prompt: "Would you ride in a fully driverless taxi today?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "philosophy-one-billion",
    category: "PHILOSOPHY",
    prompt: "Would most people stay the same person if they suddenly had a billion dollars?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "global-events-climate-optimism",
    category: "GLOBAL EVENTS",
    prompt: "Are you optimistic that the world will limit severe climate damage?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "relationships-exes-friends",
    category: "RELATIONSHIPS",
    prompt: "Can exes usually stay genuine friends?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "sports-college-athletes",
    category: "SPORTS",
    prompt: "Should college athletes be paid directly by their schools?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "politics-compulsory-voting",
    category: "POLITICS",
    prompt: "Should voting be mandatory in national elections?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "choice-free-hour",
    category: "PHILOSOPHY",
    prompt: "If you gained one free hour every day, where would it go?",
    options: [
      { id: "sleep", label: "Sleep" },
      { id: "family", label: "Family" },
      { id: "fitness", label: "Fitness" },
      { id: "hobbies", label: "Hobbies" },
    ],
  },
  {
    slug: "science-brain-computer",
    category: "SCIENCE",
    prompt: "Would you use a brain-computer implant if it improved memory?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "money-universal-basic-income",
    category: "MONEY",
    prompt: "Will a universal basic income become necessary because of automation?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "business-email-hours",
    category: "BUSINESS",
    prompt: "Should companies ban work email after hours?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "culture-restaurants-photos",
    category: "CULTURE",
    prompt: "Is taking photos of restaurant food before eating annoying?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "technology-ai-doctors",
    category: "TECHNOLOGY",
    prompt: "Would you trust an AI diagnosis more than a human doctor for routine issues?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "global-events-single-currency",
    category: "GLOBAL EVENTS",
    prompt: "Will the world ever use one dominant digital currency?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "relationships-split-bill",
    category: "RELATIONSHIPS",
    prompt: "On a first date, should splitting the bill be the default?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "sports-esports-olympics",
    category: "SPORTS",
    prompt: "Should esports be part of the Olympics?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "politics-ranked-choice",
    category: "POLITICS",
    prompt: "Would ranked-choice voting improve politics?",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    slug: "choice-best-city-size",
    category: "CULTURE",
    prompt: "What city size offers the best life?",
    options: [
      { id: "small-town", label: "Small town" },
      { id: "mid-size", label: "Mid-size city" },
      { id: "big-city", label: "Big city" },
      { id: "rural", label: "Rural area" },
    ],
  },
];

export function buildProductionQuestionSeed({
  todayDailyKey,
  now = new Date(),
  historyDays = 60,
  futureDays = 30,
}: {
  todayDailyKey?: string | null;
  now?: Date;
  historyDays?: number;
  futureDays?: number;
} = {}): ProductionSeedQuestion[] {
  const todayKey = todayDailyKey ? validateDailyKey(todayDailyKey) : dailyKeyForEasternDate(now);
  if (!Number.isInteger(historyDays) || historyDays < 0 || historyDays > 365) {
    throw new QuestionValidationError("historyDays must be an integer from 0 to 365.");
  }
  if (!Number.isInteger(futureDays) || futureDays < 0 || futureDays > 365) {
    throw new QuestionValidationError("futureDays must be an integer from 0 to 365.");
  }

  const totalDays = historyDays + 1 + futureDays;
  return Array.from({ length: totalDays }, (_, index) => {
    const dayOffset = index - historyDays;
    const dailyKey = addDaysToDailyKey(todayKey, dayOffset);
    const source = seedQuestions[index % seedQuestions.length];
    const publishAt = easternMidnightUtcForDailyKey(dailyKey);
    const closeAt = easternMidnightUtcForDailyKey(addDaysToDailyKey(dailyKey, 1));
    const type = source.options.length === 2 ? "binary" : "choice";
    const status = dayOffset < 0 ? "closed" : dayOffset === 0 ? "live" : "scheduled";
    const question: ProductionSeedQuestion = {
      ...source,
      id: `${dailyKey}-${source.slug}`,
      type,
      status,
      dailyKey,
      publishAt,
      closeAt,
    };
    if (status === "closed") {
      question.result = buildSeedResult(source, index, closeAt);
    }
    return question;
  });
}

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

function buildSeedResult(
  question: SeedQuestion,
  index: number,
  closedAt: Date,
): SeedQuestionResult {
  const optionPcts = seededOptionPercentages(question, index);
  const totalAnswers = 850 + ((index * 137) % 2400);
  const optionCounts = countsFromPercentages(question.options, optionPcts, totalAnswers);
  return {
    closedAt,
    totalAnswers,
    optionCounts,
    optionPcts,
    countedTowardScore: totalAnswers >= 50,
  };
}

function seededOptionPercentages(
  question: SeedQuestion,
  index: number,
): Record<string, number> {
  if (question.options.length === 2) {
    const first = 24 + ((index * 17 + question.prompt.length) % 53);
    return {
      [question.options[0].id]: first,
      [question.options[1].id]: 100 - first,
    };
  }

  const weights = question.options.map((option, optionIndex) => {
    return 18 + ((index * (optionIndex + 3) + option.id.length * 11) % 47);
  });
  const totalWeight = weights.reduce((sum, value) => sum + value, 0);
  let remaining = 100;
  const percentages: Record<string, number> = {};
  question.options.forEach((option, optionIndex) => {
    if (optionIndex === question.options.length - 1) {
      percentages[option.id] = remaining;
      return;
    }
    const pct = Math.max(1, Math.round((weights[optionIndex] / totalWeight) * 100));
    percentages[option.id] = pct;
    remaining -= pct;
  });
  return percentages;
}

function countsFromPercentages(
  options: SeedQuestion["options"],
  optionPcts: Record<string, number>,
  totalAnswers: number,
): Record<string, number> {
  let allocated = 0;
  const counts: Record<string, number> = {};
  options.forEach((option, index) => {
    if (index === options.length - 1) {
      counts[option.id] = Math.max(0, totalAnswers - allocated);
      return;
    }
    const count = Math.round((totalAnswers * (optionPcts[option.id] ?? 0)) / 100);
    counts[option.id] = count;
    allocated += count;
  });
  return counts;
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
