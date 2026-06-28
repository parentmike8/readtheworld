#!/usr/bin/env node
import { createRequire } from "module";

const requireFromFunctions = createRequire(new URL("../functions/package.json", import.meta.url));
const { applicationDefault, initializeApp } = requireFromFunctions("firebase-admin/app");
const { FieldValue, Timestamp, getFirestore } = requireFromFunctions("firebase-admin/firestore");
const { buildProductionQuestionSeed } = requireFromFunctions("./lib/seedQuestions.js");

const RTW_PROJECT_ID = "read-the-world-74f2a";

function usage() {
  console.error([
    "Usage:",
    "  npm run data:seed -- --project read-the-world-74f2a",
    "  npm run data:seed -- --project read-the-world-74f2a --todayDailyKey 2026-06-28 --historyDays 60 --futureDays 30",
    "",
    "Requires Application Default Credentials for the isolated Read the World Firebase project.",
  ].join("\n"));
}

function parseArgs(argv) {
  const args = {
    projectId: "",
    todayDailyKey: null,
    historyDays: undefined,
    futureDays: undefined,
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project") {
      args.projectId = argv[i + 1] ?? "";
      i += 1;
    } else if (arg === "--todayDailyKey") {
      args.todayDailyKey = argv[i + 1] ?? "";
      i += 1;
    } else if (arg === "--historyDays") {
      args.historyDays = Number(argv[i + 1]);
      i += 1;
    } else if (arg === "--futureDays") {
      args.futureDays = Number(argv[i + 1]);
      i += 1;
    } else if (arg === "--dry-run") {
      args.dryRun = true;
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

function assertSafeProject(projectId) {
  if (projectId !== RTW_PROJECT_ID) {
    throw new Error(`Refusing to seed outside ${RTW_PROJECT_ID}. Received: ${projectId || "(missing)"}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.projectId) {
    usage();
    process.exit(1);
  }
  assertSafeProject(args.projectId);

  const seedQuestions = buildProductionQuestionSeed({
    todayDailyKey: args.todayDailyKey,
    historyDays: args.historyDays,
    futureDays: args.futureDays,
  });
  const liveQuestion = seedQuestions.find((question) => question.status === "live");
  const closedCount = seedQuestions.filter((question) => question.status === "closed").length;
  const scheduledCount = seedQuestions.filter((question) => question.status === "scheduled").length;

  if (args.dryRun) {
    console.log(JSON.stringify({
      projectId: args.projectId,
      dryRun: true,
      totalQuestions: seedQuestions.length,
      closedCount,
      scheduledCount,
      liveQuestionId: liveQuestion?.id ?? null,
      firstDailyKey: seedQuestions[0]?.dailyKey ?? null,
      lastDailyKey: seedQuestions.at(-1)?.dailyKey ?? null,
    }, null, 2));
    return;
  }

  initializeApp({
    credential: applicationDefault(),
    projectId: args.projectId,
  });
  const db = getFirestore();

  const liveSnapshot = await db.collection("questions").where("status", "==", "live").limit(5).get();
  const conflictingLiveQuestions = liveSnapshot.docs
    .map((doc) => doc.id)
    .filter((questionId) => questionId !== liveQuestion?.id);
  if (conflictingLiveQuestions.length > 0) {
    throw new Error(`A different live question already exists: ${conflictingLiveQuestions.join(", ")}`);
  }

  const questionRefs = seedQuestions.map((question) => db.collection("questions").doc(question.id));
  const resultRefs = seedQuestions.map((question) =>
    question.result ? db.collection("dailyResults").doc(question.id) : null,
  );
  const existingQuestions = await Promise.all(questionRefs.map((ref) => ref.get()));
  const existingResults = await Promise.all(
    resultRefs.map((ref) => ref == null ? Promise.resolve(null) : ref.get()),
  );

  const batch = db.batch();
  let seededQuestions = 0;
  let skippedQuestions = 0;
  let seededResults = 0;
  let skippedResults = 0;

  seedQuestions.forEach((question, index) => {
    if (existingQuestions[index]?.exists) {
      skippedQuestions += 1;
    } else {
      seededQuestions += 1;
      batch.set(questionRefs[index], {
        category: question.category,
        prompt: question.prompt,
        options: question.options,
        type: question.type,
        status: question.status,
        dailyKey: question.dailyKey,
        publishAt: Timestamp.fromDate(question.publishAt),
        closeAt: Timestamp.fromDate(question.closeAt),
        totalAnswers: question.result?.totalAnswers ?? 0,
        closedAt: question.result ? Timestamp.fromDate(question.result.closedAt) : null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const resultRef = resultRefs[index];
    const result = question.result;
    if (resultRef == null || result == null) return;
    if (existingResults[index]?.exists) {
      skippedResults += 1;
      return;
    }
    seededResults += 1;
    batch.set(resultRef, {
      questionId: question.id,
      dailyKey: question.dailyKey,
      category: question.category,
      prompt: question.prompt,
      status: "closed",
      options: question.options,
      optionCounts: result.optionCounts,
      optionPcts: result.optionPcts,
      totalAnswers: result.totalAnswers,
      countedTowardScore: result.countedTowardScore,
      closedAt: Timestamp.fromDate(result.closedAt),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  if (seededQuestions > 0 || seededResults > 0) {
    await batch.commit();
  }

  console.log(JSON.stringify({
    projectId: args.projectId,
    seededQuestions,
    skippedQuestions,
    seededResults,
    skippedResults,
    totalQuestions: seedQuestions.length,
    historyDays: closedCount,
    futureDays: scheduledCount,
    todayDailyKey: liveQuestion?.dailyKey ?? null,
    liveQuestionId: liveQuestion?.id ?? null,
  }, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
