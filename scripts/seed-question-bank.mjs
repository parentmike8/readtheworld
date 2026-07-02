#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { createRequire } from "module";

const requireFromFunctions = createRequire(new URL("../functions/package.json", import.meta.url));
const { applicationDefault, initializeApp } = requireFromFunctions("firebase-admin/app");
const { FieldValue, getFirestore } = requireFromFunctions("firebase-admin/firestore");
const { bankRowsFromCsv, normalizeBankRow } = requireFromFunctions("./lib/bank.js");

const RTW_PROJECT_ID = "read-the-world-74f2a";
const SHEET_ID = "1h1QsQ5Mo_CuMvyEPQgQW4KWZHuYt77lEbVcUTZIH-4A";
const SHEET_CSV_URL =
  `https://docs.google.com/spreadsheets/d/${SHEET_ID}/export?format=csv`;

function usage() {
  console.error([
    "Seed the v2 question bank from Mike's curation sheet.",
    "",
    "Usage:",
    "  npm run bank:seed -- --project read-the-world-74f2a",
    "  npm run bank:seed -- --project read-the-world-74f2a --dry-run",
    "  npm run bank:seed -- --project read-the-world-74f2a --file path/to/export.csv",
    "",
    "Fetches the Google Sheet CSV export unless --file is given.",
    "Upserts by stable prompt hash — safe to re-run after sheet edits.",
  ].join("\n"));
}

function parseArgs(argv) {
  const args = { projectId: "", file: null, dryRun: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project") {
      args.projectId = argv[i + 1] ?? "";
      i += 1;
    } else if (arg === "--file") {
      args.file = argv[i + 1] ?? "";
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

async function loadCsv(file) {
  if (file) return readFileSync(file, "utf8");
  const response = await fetch(SHEET_CSV_URL, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(
      `Sheet fetch failed (${response.status}). Export the sheet as CSV and pass --file.`,
    );
  }
  return await response.text();
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.dryRun && args.projectId !== RTW_PROJECT_ID) {
    usage();
    throw new Error(`Refusing to seed outside ${RTW_PROJECT_ID}. Received: ${args.projectId || "(missing)"}`);
  }

  const csv = await loadCsv(args.file);
  const rows = bankRowsFromCsv(csv);
  const questions = [];
  const failures = [];
  rows.forEach((row, index) => {
    try {
      questions.push(normalizeBankRow(row));
    } catch (error) {
      failures.push({ row: index + 2, message: error.message, prompt: String(row.prompt ?? "") });
    }
  });

  const byTier = questions.reduce((acc, question) => {
    acc[question.tier] = (acc[question.tier] ?? 0) + 1;
    return acc;
  }, {});
  const uniqueIds = new Set(questions.map((question) => question.id));
  console.log(`Parsed ${rows.length} rows → ${questions.length} valid questions (${uniqueIds.size} unique ids)`);
  console.log("By tier:", byTier);
  if (failures.length > 0) {
    console.warn(`Skipped ${failures.length} rows:`);
    failures.forEach((failure) => console.warn(`  row ${failure.row}: ${failure.message} (${failure.prompt.slice(0, 50)})`));
  }
  if (uniqueIds.size !== questions.length) {
    const seen = new Set();
    for (const question of questions) {
      if (seen.has(question.id)) console.warn(`  duplicate prompt: ${question.prompt}`);
      seen.add(question.id);
    }
  }

  if (args.dryRun) {
    console.log("Dry run — nothing written.");
    return;
  }

  initializeApp({ credential: applicationDefault(), projectId: args.projectId });
  const db = getFirestore();
  let written = 0;
  for (let i = 0; i < questions.length; i += 400) {
    const batch = db.batch();
    for (const question of questions.slice(i, i + 400)) {
      batch.set(db.collection("questionBank").doc(question.id), {
        prompt: question.prompt,
        optA: question.optA,
        optB: question.optB,
        tags: question.tags,
        tier: question.tier,
        shape: question.shape,
        active: question.active,
        timesUsed: FieldValue.increment(0),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      written += 1;
    }
    await batch.commit();
  }
  console.log(`Upserted ${written} bank questions into ${args.projectId}.`);
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});
