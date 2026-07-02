#!/usr/bin/env node
/**
 * Day-one reset for the v2 rooms launch (docs/v2-implementation-spec.md §12).
 * Deletes ALL Firebase Auth users and every gameplay collection — v1 legacy
 * (questions, dailyResults, counters, leaderboards) and any v2 test data
 * (rooms, flags). Keeps: questionBank, waitlist.
 *
 * DESTRUCTIVE. Requires both the exact project id and an explicit
 * --yes-delete-everything flag.
 */
import { createRequire } from "module";

const requireFromFunctions = createRequire(new URL("../functions/package.json", import.meta.url));
const { applicationDefault, initializeApp } = requireFromFunctions("firebase-admin/app");
const { getAuth } = requireFromFunctions("firebase-admin/auth");
const { getFirestore } = requireFromFunctions("firebase-admin/firestore");

const RTW_PROJECT_ID = "read-the-world-74f2a";
const COLLECTIONS_TO_DELETE = [
  "users",
  "rooms",
  "flags",
  "links",
  "invites",
  "authHandoffs",
  "leaderboards",
  "questions",
  "dailyResults",
  "questionCounters",
  "notificationCampaigns",
];

function parseArgs(argv) {
  const args = { projectId: "", confirmed: false, dryRun: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project") {
      args.projectId = argv[i + 1] ?? "";
      i += 1;
    } else if (arg === "--yes-delete-everything") {
      args.confirmed = true;
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

function usage() {
  console.error([
    "Day-one reset: wipe auth users + gameplay data (keeps questionBank, waitlist).",
    "",
    "Usage:",
    "  node scripts/reset-day-one.mjs --project read-the-world-74f2a --dry-run",
    "  node scripts/reset-day-one.mjs --project read-the-world-74f2a --yes-delete-everything",
  ].join("\n"));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.projectId !== RTW_PROJECT_ID) {
    usage();
    throw new Error(`Refusing to reset outside ${RTW_PROJECT_ID}. Received: ${args.projectId || "(missing)"}`);
  }
  if (!args.confirmed && !args.dryRun) {
    usage();
    throw new Error("Pass --yes-delete-everything to actually delete, or --dry-run to preview.");
  }

  initializeApp({ credential: applicationDefault(), projectId: args.projectId });
  const auth = getAuth();
  const db = getFirestore();

  // ── auth users ──
  let userCount = 0;
  let pageToken;
  const uids = [];
  do {
    const page = await auth.listUsers(1000, pageToken);
    uids.push(...page.users.map((user) => user.uid));
    pageToken = page.pageToken;
  } while (pageToken);
  userCount = uids.length;
  console.log(`Auth users found: ${userCount}`);

  if (!args.dryRun && uids.length > 0) {
    for (let i = 0; i < uids.length; i += 1000) {
      const result = await auth.deleteUsers(uids.slice(i, i + 1000));
      console.log(`  deleted ${result.successCount}, failed ${result.failureCount}`);
    }
  }

  // ── firestore collections (recursive — includes subcollections) ──
  for (const collectionId of COLLECTIONS_TO_DELETE) {
    const snap = await db.collection(collectionId).count().get();
    const count = snap.data().count;
    console.log(`${collectionId}: ${count} docs${args.dryRun ? "" : " — deleting…"}`);
    if (!args.dryRun && count > 0) {
      await db.recursiveDelete(db.collection(collectionId));
    }
  }

  const bankCount = (await db.collection("questionBank").count().get()).data().count;
  console.log(`questionBank kept: ${bankCount} questions`);
  console.log(args.dryRun ? "Dry run — nothing deleted." : "Day-one reset complete.");
  if (!args.dryRun) {
    console.log("Next: the 00:00 ET rollover (or a manual run) will recreate rooms/world.");
  }
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});
