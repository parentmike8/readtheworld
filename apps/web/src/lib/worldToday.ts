import { serverFirestore } from "./serverFirebase";

export type WorldTodayCard = {
  dailyKey: string;
  dateLabel: string;
  answerCount: number;
  memberCount: number;
  worldGoal: number;
  questions: Array<{
    qid: string;
    prompt: string;
    tag: string;
    optA: string;
    optB: string;
  }>;
};

/** Marketing copy stands in whenever the world day is unreadable. */
export const fallbackWorldToday: WorldTodayCard = {
  dailyKey: "",
  dateLabel: "",
  answerCount: 0,
  memberCount: 0,
  worldGoal: 5000,
  questions: [
    {
      qid: "fallback-hot-dog",
      prompt: "Is a hot dog a sandwich?",
      tag: "Food & Drink",
      optA: "Yes",
      optB: "No",
    },
    {
      qid: "fallback-exact-date",
      prompt: "Would you want to know the exact date you'll die?",
      tag: "Deep",
      optA: "Yes",
      optB: "No",
    },
    {
      qid: "fallback-friends",
      prompt: "Can men and women truly be just friends?",
      tag: "Belief",
      optA: "Yes",
      optB: "No",
    },
  ],
};

/** Today's three World questions (rooms/world/days/{currentDailyKey}). */
export async function readWorldToday(): Promise<WorldTodayCard> {
  try {
    const db = serverFirestore();
    const worldSnap = await within(
      db.collection("rooms").doc("world").get(),
      1200,
    );
    const worldData = worldSnap.data();
    const dailyKey = stringValue(worldData?.currentDailyKey);
    if (!dailyKey) return fallbackWorldToday;

    const daySnap = await within(
      db.collection("rooms").doc("world")
        .collection("days").doc(dailyKey)
        .get(),
      1200,
    );
    const rawQuestions = daySnap.data()?.questions;
    if (!Array.isArray(rawQuestions)) return fallbackWorldToday;

    const questions = rawQuestions
      .filter((question) => question && typeof question === "object" && question.pulled !== true)
      .map((question: Record<string, unknown>, index) => ({
        qid: stringValue(question.qid) ?? `${dailyKey}-${index + 1}`,
        prompt: stringValue(question.prompt) ?? "",
        tag: stringValue(question.tag) ?? "Today",
        optA: stringValue(question.optA) ?? "Yes",
        optB: stringValue(question.optB) ?? "No",
      }))
      .filter((question) => question.prompt.length > 0)
      .slice(0, 3);
    if (questions.length === 0) return fallbackWorldToday;

    return {
      dailyKey,
      dateLabel: dateLabel(dailyKey),
      answerCount: finiteNumber(daySnap.data()?.answerCount),
      memberCount: finiteNumber(worldData?.memberCount),
      worldGoal: positiveNumber(worldData?.worldGoal, 5000),
      questions,
    };
  } catch {
    return fallbackWorldToday;
  }
}

function finiteNumber(value: unknown) {
  const number = Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

function positiveNumber(value: unknown, fallback: number) {
  const number = finiteNumber(value);
  return number > 0 ? number : fallback;
}

function within<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("World data timed out")), timeoutMs);
    promise.then(
      (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
      (error) => {
        clearTimeout(timeout);
        reject(error);
      },
    );
  });
}

function stringValue(value: unknown) {
  if (value == null) return null;
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

function dateLabel(dailyKey: string) {
  const date = new Date(`${dailyKey}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return dailyKey.toUpperCase();
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(date).toUpperCase();
}
