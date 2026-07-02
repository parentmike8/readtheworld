#!/usr/bin/env node
/**
 * Seeds the local emulator suite for v2 QA: question bank from the CSV
 * fixture, the World room, and a live world day for today (Eastern).
 * Requires FIRESTORE_EMULATOR_HOST (refuses to touch production).
 */
import { readFileSync } from "node:fs";
import { createRequire } from "module";

const requireFromFunctions = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp } = requireFromFunctions("firebase-admin/app");
const { FieldValue, getFirestore } = requireFromFunctions("firebase-admin/firestore");
const { bankRowsFromCsv, normalizeBankRow } = requireFromFunctions("./lib/bank.js");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Set FIRESTORE_EMULATOR_HOST (e.g. localhost:8080) — this script is emulator-only.");
  process.exit(1);
}

initializeApp({ projectId: "read-the-world-74f2a" });
const db = getFirestore();

function easternDailyKey(offsetDays = 0) {
  const eastern = new Date().toLocaleDateString("en-CA", { timeZone: "America/New_York" });
  const [year, month, day] = eastern.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + offsetDays));
  return date.toISOString().slice(0, 10);
}

const csv = readFileSync(new URL("../data/question-bank.csv", import.meta.url), "utf8");
const rows = bankRowsFromCsv(csv);
const questions = [];
for (const row of rows) {
  try {
    questions.push(normalizeBankRow(row));
  } catch {
    // skip malformed rows in QA
  }
}

let batch = db.batch();
let inBatch = 0;
for (const question of questions) {
  batch.set(db.collection("questionBank").doc(question.id), {
    prompt: question.prompt,
    optA: question.optA,
    optB: question.optB,
    tags: question.tags,
    tier: question.tier,
    shape: question.shape,
    active: question.active,
    timesUsed: 0,
    updatedAt: FieldValue.serverTimestamp(),
  });
  inBatch += 1;
  if (inBatch >= 400) {
    await batch.commit();
    batch = db.batch();
    inBatch = 0;
  }
}
if (inBatch > 0) await batch.commit();
console.log(`Seeded ${questions.length} bank questions into the emulator.`);

// World room + today's world day (3 work-safe questions, low thresholds so
// QA can watch counts move).
const todayKey = easternDailyKey();
const worldQuestions = questions
  .filter((question) => question.tier === "work-safe")
  .slice(0, 3)
  .map((question) => ({
    qid: question.id,
    prompt: question.prompt,
    optA: question.optA,
    optB: question.optB,
    tag: question.tags[0] ?? "Everyday",
    shape: question.shape,
    tier: question.tier,
    custom: false,
    authorUid: null,
    authorName: null,
    pulled: false,
    threshold: 1000,
  }));

await db.collection("rooms").doc("world").set({
  name: "The World",
  color: "oklch(0.40 0.11 256)",
  tier: "normal",
  cats: ["All"],
  customEnabled: false,
  revealAnswersDefault: false,
  createdBy: "system",
  isWorld: true,
  worldGoal: 5000,
  memberCount: 2847,
  usedQuestionIds: worldQuestions.map((question) => question.qid),
  inviteCode: null,
  currentDailyKey: todayKey,
  createdAt: FieldValue.serverTimestamp(),
  updatedAt: FieldValue.serverTimestamp(),
});
await db.collection("rooms").doc("world").collection("days").doc(todayKey).set({
  dailyKey: todayKey,
  status: "live",
  questions: worldQuestions,
  answerCount: 0,
  answerCounts: { [worldQuestions[0].qid]: 812, [worldQuestions[1].qid]: 305, [worldQuestions[2].qid]: 58 },
  createdAt: FieldValue.serverTimestamp(),
});
console.log(`World room live for ${todayKey}: ${worldQuestions.map((question) => question.prompt).join(" · ")}`);
