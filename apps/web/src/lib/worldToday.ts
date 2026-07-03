import { serverFirestore } from "./serverFirebase";

export type WorldTodayCard = {
  dateLabel: string;
  questions: Array<{ prompt: string; tag: string }>;
};

/** Marketing copy stands in whenever the world day is unreadable. */
export const fallbackWorldToday: WorldTodayCard = {
  dateLabel: "",
  questions: [
    { prompt: "Is a hot dog a sandwich?", tag: "Food & Drink" },
    { prompt: "Would you want to know the exact date you'll die?", tag: "Deep" },
    { prompt: "Can men and women truly be just friends?", tag: "Belief" },
  ],
};

/** Today's three World questions (rooms/world/days/{currentDailyKey}). */
export async function readWorldToday(): Promise<WorldTodayCard> {
  try {
    const db = serverFirestore();
    const worldSnap = await db.collection("rooms").doc("world").get();
    const dailyKey = stringValue(worldSnap.data()?.currentDailyKey);
    if (!dailyKey) return fallbackWorldToday;

    const daySnap = await db
      .collection("rooms").doc("world")
      .collection("days").doc(dailyKey)
      .get();
    const rawQuestions = daySnap.data()?.questions;
    if (!Array.isArray(rawQuestions)) return fallbackWorldToday;

    const questions = rawQuestions
      .filter((question) => question && typeof question === "object" && question.pulled !== true)
      .map((question: Record<string, unknown>) => ({
        prompt: stringValue(question.prompt) ?? "",
        tag: stringValue(question.tag) ?? "",
      }))
      .filter((question) => question.prompt.length > 0)
      .slice(0, 3);
    if (questions.length === 0) return fallbackWorldToday;

    return { dateLabel: dateLabel(dailyKey), questions };
  } catch {
    return fallbackWorldToday;
  }
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
