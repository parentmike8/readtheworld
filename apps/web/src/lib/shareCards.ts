import { serverFirestore } from "./serverFirebase";

type FirestoreRecord = Record<string, unknown>;

export type ShareCard = {
  code: string;
  type: "invite" | "result" | "today";
  title: string;
  description: string;
  eyebrow: string;
  category: string;
  dateLabel: string;
  prompt: string;
  destinationUrl: string;
};

const marketingUrl = "https://readtheworld.today";
const appUrl = "https://app.readtheworld.today";
const shortUrl = "https://rtw.codes";
const shortCodePattern = /^[A-Z0-9]{4,16}$/;

export const fallbackShareCard: ShareCard = {
  code: "",
  type: "today",
  title: "Read the World",
  description: "One shared question a day. Answer for yourself, then predict how the world will answer.",
  eyebrow: "Today's question",
  category: "Daily read",
  dateLabel: "",
  prompt: "Can you read the world today?",
  destinationUrl: marketingUrl,
};

export async function readShareCard(rawCode: string): Promise<ShareCard | null> {
  if (rawCode.trim().toLowerCase() === "today") return readTodayShareCard();
  return readShareCardByCode(rawCode);
}

export async function readShareCardByCode(rawCode: string): Promise<ShareCard | null> {
  const code = normalizeCode(rawCode);
  if (!code) return null;

  const db = serverFirestore();
  const linkSnap = await db.collection("links").doc(code).get();
  if (!linkSnap.exists) return null;

  const link = linkSnap.data() ?? {};
  const type = stringValue(link.type);
  if ((type !== "invite" && type !== "result") || expired(link.expiresAt)) {
    return null;
  }

  if (type === "invite") {
    const liveQuestion = await readLiveQuestion();
    const question = liveQuestion ?? fallbackShareCard;
    return {
      code,
      type,
      title: "Can you read the world today?",
      description: "Answer today's question, then predict how everyone else answered.",
      eyebrow: "Today's question",
      category: question.category,
      dateLabel: question.dateLabel,
      prompt: question.prompt,
      destinationUrl: `${shortUrl}/${encodeURIComponent(code)}`,
    };
  }

  const targetId = stringValue(link.targetId);
  if (!targetId) return null;

  const question = await readQuestion(targetId);
  if (!question || question.status !== "closed") return null;

  return {
    code,
    type,
    title: "Read the World result",
    description: "See how close this read was to the world.",
    eyebrow: "Daily result",
    category: question.category,
    dateLabel: question.dateLabel,
    prompt: question.prompt,
    destinationUrl: `${shortUrl}/${encodeURIComponent(code)}`,
  };
}

export async function readTodayShareCard(): Promise<ShareCard> {
  const liveQuestion = await readLiveQuestion();
  if (!liveQuestion) return fallbackShareCard;

  return {
    ...fallbackShareCard,
    title: "Can you read the world today?",
    description: "Answer today's question, then predict how everyone else answered.",
    eyebrow: "Today's question",
    category: liveQuestion.category,
    dateLabel: liveQuestion.dateLabel,
    prompt: liveQuestion.prompt,
    destinationUrl: `${appUrl}/today`,
  };
}

function normalizeCode(value: string) {
  const code = value.trim().toUpperCase();
  return shortCodePattern.test(code) ? code : null;
}

async function readLiveQuestion() {
  const db = serverFirestore();
  const snapshot = await db.collection("questions")
    .where("status", "==", "live")
    .limit(1)
    .get();
  const doc = snapshot.docs[0];
  if (!doc) return null;
  return questionFromData(doc.id, doc.data(), "live");
}

async function readQuestion(questionId: string) {
  const db = serverFirestore();
  const questionSnap = await db.collection("questions").doc(questionId).get();
  const data = questionSnap.data();
  if (data) return questionFromData(questionSnap.id, data, stringValue(data.status) ?? "");

  const resultSnap = await db.collection("dailyResults").doc(questionId).get();
  const resultData = resultSnap.data();
  return resultData ? questionFromData(resultSnap.id, resultData, "closed") : null;
}

function questionFromData(id: string, data: FirestoreRecord, status: string) {
  const dailyKey = stringValue(data.dailyKey) ?? dailyKeyFromId(id);
  return {
    status,
    category: displayCategory(stringValue(data.category) ?? "Daily read"),
    dateLabel: dateLabel(dailyKey),
    prompt: stringValue(data.prompt) ?? fallbackShareCard.prompt,
  };
}

function stringValue(value: unknown) {
  if (value == null) return null;
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

function expired(value: unknown) {
  const date = dateFromTimestamp(value);
  return date != null && date.getTime() <= Date.now();
}

function dateFromTimestamp(value: unknown): Date | null {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    const date = value.toDate() as Date;
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function dailyKeyFromId(id: string) {
  return /^\d{4}-\d{2}-\d{2}/.exec(id)?.[0] ?? "";
}

function dateLabel(dailyKey: string) {
  if (!dailyKey) return "";
  const date = new Date(`${dailyKey}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return dailyKey.toUpperCase();
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(date).toUpperCase();
}

function displayCategory(value: string) {
  return value
    .replaceAll("_", " ")
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => `${word[0]?.toUpperCase() ?? ""}${word.slice(1).toLowerCase()}`)
    .join(" ");
}
