#!/usr/bin/env node
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

const RTW_PROJECT_ID = "read-the-world-74f2a";

function usage() {
  console.error([
    "Usage:",
    "  npm run admin:claim -- --email admin@example.com --project read-the-world-74f2a",
    "  npm run admin:claim -- --email admin@example.com --project read-the-world-74f2a --revoke",
    "",
    "Requires Application Default Credentials or a service account for the isolated Read the World Firebase project.",
  ].join("\n"));
}

function parseArgs(argv) {
  const args = {
    admin: true,
    email: "",
    projectId: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--email") {
      args.email = argv[i + 1] ?? "";
      i += 1;
    } else if (arg === "--project") {
      args.projectId = argv[i + 1] ?? "";
      i += 1;
    } else if (arg === "--revoke") {
      args.admin = false;
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
    throw new Error(`Refusing to write admin claims outside ${RTW_PROJECT_ID}. Received: ${projectId || "(missing)"}`);
  }
}

async function main() {
  const { admin, email, projectId } = parseArgs(process.argv.slice(2));
  if (!email || !projectId) {
    usage();
    process.exit(1);
  }
  assertSafeProject(projectId);

  initializeApp({
    credential: applicationDefault(),
    projectId,
  });

  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const claims = { ...(user.customClaims ?? {}) };
  if (admin) {
    claims.admin = true;
  } else {
    delete claims.admin;
  }

  await auth.setCustomUserClaims(user.uid, claims);
  console.log(JSON.stringify({
    email,
    uid: user.uid,
    projectId,
    admin,
  }, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
