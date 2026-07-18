#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const EXPECTED_PROJECT_ID = "read-the-world-74f2a";
const EXPECTED_PROJECT_NUMBER = "863014025103";
const EXPECTED_GOOGLE_ACCOUNT = "mike@readtheworld.today";
const EXPECTED_GITHUB_ACCOUNT = "parentmike8";
const EXPECTED_REMOTE = "parentmike8/readtheworld";
const EXPECTED_IOS_BUNDLE_ID = "today.readtheworld.app";
const EXPECTED_ANDROID_PACKAGE_NAME = "today.readtheworld.app";

const results = [];

function add(status, label, detail = "") {
  results.push({ status, label, detail });
}

function rel(filePath) {
  return path.join(ROOT, filePath);
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    encoding: "utf8",
    shell: false,
  });
  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    output: `${result.stdout ?? ""}${result.stderr ?? ""}`.trim(),
  };
}

function readJson(filePath) {
  if (!existsSync(rel(filePath))) return null;
  return JSON.parse(readFileSync(rel(filePath), "utf8"));
}

function parseDotenv(text) {
  const values = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line);
    if (!match) continue;
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    values[match[1]] = value;
  }
  return values;
}

function loadEnv() {
  const files = [".env", ".env.local", "apps/web/.env", "apps/web/.env.local"];
  const loaded = {};
  const present = [];
  for (const file of files) {
    if (!existsSync(rel(file))) continue;
    Object.assign(loaded, parseDotenv(readFileSync(rel(file), "utf8")));
    present.push(file);
  }
  add(
    present.length > 0 ? "ok" : "warn",
    "Local env files",
    present.length > 0
      ? `Loaded ${present.join(", ")}`
      : "No local env file found; shell environment will still be checked.",
  );
  return { ...loaded, ...process.env };
}

function loadFunctionsRuntimeEnv() {
  const files = [
    "functions/.env",
    `functions/.env.${EXPECTED_PROJECT_ID}`,
    "functions/.env.default",
  ];
  const loaded = {};
  const present = [];
  for (const file of files) {
    if (!existsSync(rel(file))) continue;
    Object.assign(loaded, parseDotenv(readFileSync(rel(file), "utf8")));
    present.push(file);
  }
  add(
    present.length > 0 ? "ok" : "block",
    "Functions runtime env file",
    present.length > 0
      ? `Loaded ${present.join(", ")}`
      : `Create functions/.env.${EXPECTED_PROJECT_ID} from functions/.env.example before deploying Functions.`,
  );
  return loaded;
}

function missingKeys(env, keys) {
  return keys.filter((key) => String(env[key] ?? "").trim().length === 0);
}

function checkExpectedValue(env, key, expected) {
  const value = String(env[key] ?? "").trim();
  if (!value) {
    add("block", key, `${key} is required.`);
  } else if (value !== expected) {
    add("block", key, `Expected ${expected}, found ${value}.`);
  } else {
    add("ok", key, value);
  }
}

function checkNonPlaceholderValue(env, key, placeholderPattern) {
  const value = String(env[key] ?? "").trim();
  if (!value) {
    add("block", key, `${key} is required.`);
  } else if (placeholderPattern.test(value)) {
    add("block", key, `${key} still looks like a placeholder.`);
  } else {
    add("ok", key, value);
  }
}

function flagWorkValue(label, value) {
  if (/covet|covetai|covet-org|smart\.vet/i.test(value)) {
    add("block", label, "Value appears to reference a CoVet/work context.");
  }
}

function checkAccounts() {
  const remote = run("git", ["remote", "get-url", "origin"]);
  if (remote.status !== 0) {
    add("block", "Git remote", "Could not read origin remote.");
  } else if (!remote.stdout.includes(EXPECTED_REMOTE)) {
    add("block", "Git remote", `Expected ${EXPECTED_REMOTE}, found ${remote.stdout.trim()}.`);
  } else {
    add("ok", "Git remote", remote.stdout.trim());
  }

  const gh = run("gh", ["auth", "status"]);
  if (gh.output.includes("not found") || gh.output.includes("is not installed")) {
    add("block", "GitHub CLI", "gh is required before deploy/push checks.");
  } else {
    const accountMatch = /account\s+([^\s]+)/.exec(gh.output);
    const account = accountMatch?.[1] ?? "";
    flagWorkValue("GitHub active auth", account);
    if (account !== EXPECTED_GITHUB_ACCOUNT) {
      add("block", "GitHub auth", `Expected ${EXPECTED_GITHUB_ACCOUNT}; current status says ${account || "unknown"}.`);
    } else {
      add("ok", "GitHub auth", `Logged in as ${account}.`);
    }
    const inactiveWorkAccounts = [...gh.output.matchAll(/account\s+([^\s]+)[\s\S]*?Active account:\s+false/g)]
      .map((match) => match[1])
      .filter((name) => /covet|covetai|covet-org|smart\.vet/i.test(name));
    if (inactiveWorkAccounts.length > 0) {
      add(
        "warn",
        "GitHub inactive accounts",
        `Inactive stored login(s) present but not active: ${inactiveWorkAccounts.join(", ")}.`,
      );
    }
  }

  const gcloud = run("gcloud", ["auth", "list", "--format=json"]);
  if (gcloud.status !== 0) {
    add("block", "Google Cloud auth", gcloud.output || "gcloud auth list failed.");
  } else {
    flagWorkValue("Google Cloud auth", gcloud.output);
    let active = "";
    try {
      const rows = JSON.parse(gcloud.stdout);
      active = rows.find((row) => row.status === "ACTIVE")?.account ?? "";
    } catch {
      active = "";
    }
    if (active !== EXPECTED_GOOGLE_ACCOUNT) {
      add("block", "Google Cloud auth", `Expected active account ${EXPECTED_GOOGLE_ACCOUNT}; found ${active || "none"}.`);
    } else {
      add("ok", "Google Cloud auth", `Active account ${active}.`);
    }
  }

  const firebase = run("firebase", ["login:list"]);
  if (firebase.output.includes("No authorized accounts")) {
    add("block", "Firebase CLI auth", `Run firebase login with ${EXPECTED_GOOGLE_ACCOUNT}.`);
  } else {
    flagWorkValue("Firebase CLI auth", firebase.output);
    const emails = [...firebase.output.matchAll(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi)]
      .map((match) => match[0].toLowerCase());
    if (!emails.includes(EXPECTED_GOOGLE_ACCOUNT)) {
      add("block", "Firebase CLI auth", `Expected ${EXPECTED_GOOGLE_ACCOUNT}; found ${emails.join(", ") || "unknown"}.`);
    } else {
      add("ok", "Firebase CLI auth", `Authorized account ${EXPECTED_GOOGLE_ACCOUNT}.`);
    }
  }

  const firebaseProjectAccess = run("npx", [
    "-y",
    "firebase-tools@15.22.3",
    "projects:list",
    "--json",
  ]);
  if (firebaseProjectAccess.status !== 0) {
    add(
      "block",
      "Firebase CLI credential validity",
      firebaseProjectAccess.output || "Could not verify Firebase project access.",
    );
  } else if (!firebaseProjectAccess.stdout.includes(EXPECTED_PROJECT_ID)) {
    add(
      "block",
      "Firebase CLI project access",
      `Authenticated account cannot see ${EXPECTED_PROJECT_ID}.`,
    );
  } else {
    add("ok", "Firebase CLI credential validity", `Can access ${EXPECTED_PROJECT_ID}.`);
  }
}

function checkFirebaseFiles() {
  const firebaseJson = readJson("firebase.json");
  if (!firebaseJson) {
    add("block", "firebase.json", "Missing firebase.json.");
  } else {
    const hostingTargets = new Set((firebaseJson.hosting ?? []).map((item) => item.target));
    for (const target of ["app", "links", "redirect"]) {
      if (!hostingTargets.has(target)) {
        add("block", `Firebase Hosting target ${target}`, "Missing from firebase.json.");
      } else {
        add("ok", `Firebase Hosting target ${target}`, "Configured.");
      }
    }
    const functionsRuntime = firebaseJson.functions?.[0]?.runtime;
    if (functionsRuntime === "nodejs22") {
      add("ok", "Functions runtime", "nodejs22");
    } else {
      add("block", "Functions runtime", `Expected nodejs22, found ${functionsRuntime ?? "missing"}.`);
    }
  }

  const firebaserc = readJson(".firebaserc");
  if (!firebaserc) {
    add("block", ".firebaserc", "Copy .firebaserc.example after account checks pass and fill hosting site IDs.");
  } else {
    const project = firebaserc.projects?.default;
    if (project !== EXPECTED_PROJECT_ID) {
      add("block", ".firebaserc project", `Expected ${EXPECTED_PROJECT_ID}, found ${project ?? "missing"}.`);
    } else {
      add("ok", ".firebaserc project", project);
    }
    const targets = firebaserc.targets?.[EXPECTED_PROJECT_ID]?.hosting ?? {};
    for (const target of ["app", "links", "redirect"]) {
      const sites = targets[target] ?? [];
      if (!Array.isArray(sites) || sites.length === 0 || sites.some((site) => /YOUR_|TODO|PLACEHOLDER/i.test(site))) {
        add("block", `.firebaserc hosting target ${target}`, "Fill the real Firebase Hosting site ID.");
      } else {
        add("ok", `.firebaserc hosting target ${target}`, sites.join(", "));
      }
    }
  }

  if (existsSync(rel("apps/web/apphosting.yaml"))) {
    const appHosting = readFileSync(rel("apps/web/apphosting.yaml"), "utf8");
    add("ok", "Firebase App Hosting config", "apps/web/apphosting.yaml");
    for (const key of [
      "NEXT_PUBLIC_FIREBASE_API_KEY",
      "NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN",
      "NEXT_PUBLIC_FIREBASE_PROJECT_ID",
      "NEXT_PUBLIC_FIREBASE_APP_ID",
    ]) {
      if (appHosting.includes(`variable: ${key}`)) {
        add("ok", `App Hosting env ${key}`, "Declared for build/runtime.");
      } else {
        add("block", `App Hosting env ${key}`, "Missing from apps/web/apphosting.yaml.");
      }
    }
  } else {
    add("block", "Firebase App Hosting config", "Missing apps/web/apphosting.yaml.");
  }

  if (existsSync(rel("apps/web/src/proxy.ts"))) {
    const proxy = readFileSync(rel("apps/web/src/proxy.ts"), "utf8");
    if (
      proxy.includes("admin.readtheworld.today") &&
      proxy.includes('url.pathname = "/admin"') &&
      proxy.includes("NextResponse.rewrite")
    ) {
      add("ok", "Admin host routing", "admin.readtheworld.today rewrites to /admin.");
    } else {
      add("block", "Admin host routing", "Expected admin.readtheworld.today host rewrite to /admin in apps/web/src/proxy.ts.");
    }
  } else {
    add("block", "Admin host routing", "Missing apps/web/src/proxy.ts.");
  }

  if (!existsSync(rel("apps/app/web/firebase-messaging-sw.js"))) {
    add("block", "Flutter web FCM service worker", "Missing apps/app/web/firebase-messaging-sw.js.");
  } else {
    const worker = readFileSync(rel("apps/app/web/firebase-messaging-sw.js"), "utf8");
    if (
      worker.includes("/__/firebase/init.js") &&
      worker.includes("firebase-messaging-compat.js")
    ) {
      add("ok", "Flutter web FCM service worker", "Configured for Firebase Hosting reserved init.");
    } else {
      add("block", "Flutter web FCM service worker", "Expected Firebase Hosting reserved init and messaging SDK imports.");
    }
  }
  if (existsSync(rel("apps/app/build/web"))) {
    if (existsSync(rel("apps/app/build/web/firebase-messaging-sw.js"))) {
      add("ok", "Flutter web build FCM service worker", "Copied into apps/app/build/web.");
    } else {
      add("block", "Flutter web build FCM service worker", "Run npm run app:build:web so the worker is copied into the deploy artifact.");
    }
  }

  if (existsSync(rel("apps/app/android/app/src/main/AndroidManifest.xml"))) {
    const androidManifest = readFileSync(rel("apps/app/android/app/src/main/AndroidManifest.xml"), "utf8");
    if (
      androidManifest.includes(`android:host="rtw.codes"`) &&
      androidManifest.includes('android:autoVerify="true"')
    ) {
      add("ok", "Android App Links manifest", "rtw.codes autoVerify configured.");
    } else {
      add("block", "Android App Links manifest", "Expected rtw.codes autoVerify intent filter.");
    }
    if (androidManifest.includes('android:screenOrientation="portrait"')) {
      add("ok", "Android orientation", "Portrait locked.");
    } else {
      add("block", "Android orientation", "Expected MainActivity to lock portrait orientation.");
    }
  } else {
    add("block", "Android manifest", "Missing apps/app/android/app/src/main/AndroidManifest.xml.");
  }

  if (existsSync(rel("apps/app/ios/Runner/Info.plist"))) {
    const iosInfo = readFileSync(rel("apps/app/ios/Runner/Info.plist"), "utf8");
    if (
      iosInfo.includes("<key>CFBundleDisplayName</key>") &&
      iosInfo.includes("<string>Read the World</string>")
    ) {
      add("ok", "iOS display name", "Read the World.");
    } else {
      add("block", "iOS display name", "Expected CFBundleDisplayName to be Read the World.");
    }
    if (
      iosInfo.includes("UIInterfaceOrientationPortrait") &&
      !iosInfo.includes("UIInterfaceOrientationLandscapeLeft") &&
      !iosInfo.includes("UIInterfaceOrientationLandscapeRight") &&
      !iosInfo.includes("UIInterfaceOrientationPortraitUpsideDown")
    ) {
      add("ok", "iOS orientation", "Portrait locked.");
    } else {
      add("block", "iOS orientation", "Expected portrait-only supported orientations.");
    }
  } else {
    add("block", "iOS Info.plist", "Missing apps/app/ios/Runner/Info.plist.");
  }

  const remoteConfig = readJson("firebase/remoteconfig.template.json");
  if (!remoteConfig) {
    add("block", "Remote Config template", "Missing firebase/remoteconfig.template.json.");
  } else {
    for (const key of [
      "feature_party_mode",
      "feature_friends",
      "feature_friends_leaderboard",
      "feature_result_sharing",
      "feature_onboarding_demographics",
    ]) {
      const value = remoteConfig.parameters?.[key]?.defaultValue?.value;
      if (value === "true") {
        add("ok", `Remote Config ${key}`, "Default true.");
      } else {
        add("block", `Remote Config ${key}`, `Expected default true, found ${value ?? "missing"}.`);
      }
    }
  }

  const indexes = readJson("firebase/firestore.indexes.json");
  if (!indexes) {
    add("block", "Firestore indexes", "Missing firebase/firestore.indexes.json.");
  } else {
    const requiredIndexes = [
      {
        label: "answers question official",
        collectionGroup: "answers",
        queryScope: "COLLECTION_GROUP",
        fields: ["questionId:ASCENDING", "official:ASCENDING"],
      },
      {
        label: "scheduled questions publish",
        collectionGroup: "questions",
        queryScope: "COLLECTION",
        fields: ["status:ASCENDING", "publishAt:ASCENDING"],
      },
      {
        label: "live questions close",
        collectionGroup: "questions",
        queryScope: "COLLECTION",
        fields: ["status:ASCENDING", "closeAt:ASCENDING"],
      },
    ];
    for (const required of requiredIndexes) {
      if (hasFirestoreIndex(indexes.indexes ?? [], required)) {
        add("ok", `Firestore index ${required.label}`, "Configured.");
      } else {
        add("block", `Firestore index ${required.label}`, "Missing or wrong queryScope/fields.");
      }
    }

    const requiredFieldOverrides = [
      {
        label: "friends uid",
        collectionGroup: "friends",
        fieldPath: "uid",
        indexes: [
          "COLLECTION:ASCENDING",
          "COLLECTION:DESCENDING",
          "COLLECTION_GROUP:ASCENDING",
        ],
      },
      {
        label: "notification tokens enabled",
        collectionGroup: "notificationTokens",
        fieldPath: "enabled",
        indexes: [
          "COLLECTION:ASCENDING",
          "COLLECTION:DESCENDING",
          "COLLECTION_GROUP:ASCENDING",
        ],
      },
    ];
    for (const required of requiredFieldOverrides) {
      if (hasFirestoreFieldOverride(indexes.fieldOverrides ?? [], required)) {
        add("ok", `Firestore field override ${required.label}`, "Collection and collection-group scopes configured.");
      } else {
        add(
          "block",
          `Firestore field override ${required.label}`,
          "Missing collection defaults or required collection-group scope.",
        );
      }
    }
  }
}

function hasFirestoreIndex(indexes, required) {
  return indexes.some((index) => {
    if ((required.collectionId ?? null) !== (index.collectionId ?? null)) return false;
    if ((required.collectionGroup ?? null) !== (index.collectionGroup ?? null)) return false;
    if (required.queryScope !== index.queryScope) return false;
    const fields = (index.fields ?? []).map((field) => `${field.fieldPath}:${field.order}`);
    return required.fields.length === fields.length &&
      required.fields.every((field, index) => field === fields[index]);
  });
}

function hasFirestoreFieldOverride(fieldOverrides, required) {
  const override = fieldOverrides.find((item) =>
    item.collectionGroup === required.collectionGroup &&
    item.fieldPath === required.fieldPath,
  );
  if (!override) return false;
  const configured = new Set((override.indexes ?? []).map((index) =>
    `${index.queryScope}:${index.order ?? index.arrayConfig ?? ""}`,
  ));
  return required.indexes.every((index) => configured.has(index));
}

function checkEnvironment() {
  const env = loadEnv();
  const requiredWeb = [
    "NEXT_PUBLIC_FIREBASE_API_KEY",
    "NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN",
    "NEXT_PUBLIC_FIREBASE_PROJECT_ID",
    "NEXT_PUBLIC_FIREBASE_APP_ID",
  ];
  const missingWeb = missingKeys(env, requiredWeb);
  if (missingWeb.length === 0) {
    add("ok", "Next Firebase env", "Required public Firebase values are present.");
  } else {
    add("block", "Next Firebase env", `Missing ${missingWeb.join(", ")}.`);
  }
  checkExpectedValue(env, "NEXT_PUBLIC_FIREBASE_PROJECT_ID", EXPECTED_PROJECT_ID);
  checkExpectedValue(env, "NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN", `${EXPECTED_PROJECT_ID}.firebaseapp.com`);

  const requiredFlutter = [
    "RTW_FIREBASE_CONFIGURED",
    "RTW_FIREBASE_API_KEY",
    "RTW_FIREBASE_APP_ID",
    "RTW_FIREBASE_ANDROID_API_KEY",
    "RTW_FIREBASE_ANDROID_APP_ID",
    "RTW_FIREBASE_IOS_API_KEY",
    "RTW_FIREBASE_IOS_APP_ID",
    "RTW_FIREBASE_SENDER_ID",
    "RTW_FIREBASE_PROJECT_ID",
    "RTW_FIREBASE_AUTH_DOMAIN",
    "RTW_FIREBASE_STORAGE_BUCKET",
    "RTW_GOOGLE_WEB_CLIENT_ID",
    "RTW_GOOGLE_IOS_CLIENT_ID",
    "RTW_RECAPTCHA_ENTERPRISE_SITE_KEY",
    "RTW_WEB_PUSH_VAPID_KEY",
  ];
  const missingFlutter = missingKeys(env, requiredFlutter);
  if (missingFlutter.length === 0) {
    add("ok", "Flutter build env", "Required --dart-define source values are present.");
  } else {
    add("block", "Flutter build env", `Missing ${missingFlutter.join(", ")}.`);
  }
  checkExpectedValue(env, "RTW_FIREBASE_CONFIGURED", "true");
  checkExpectedValue(env, "RTW_FIREBASE_PROJECT_ID", EXPECTED_PROJECT_ID);
  checkExpectedValue(env, "RTW_FIREBASE_SENDER_ID", EXPECTED_PROJECT_NUMBER);
  checkExpectedValue(env, "RTW_FIREBASE_AUTH_DOMAIN", `${EXPECTED_PROJECT_ID}.firebaseapp.com`);

  if (existsSync(rel("apps/app/ios/Runner/Info.plist"))) {
    const plist = readFileSync(rel("apps/app/ios/Runner/Info.plist"), "utf8");
    if (
      plist.includes("CFBundleURLTypes") &&
      !plist.includes("REPLACE_WITH_GOOGLE_REVERSED_CLIENT_ID")
    ) {
      add("ok", "iOS Google URL scheme", "Configured in Runner/Info.plist.");
    } else {
      add("block", "iOS Google URL scheme", "Replace REPLACE_WITH_GOOGLE_REVERSED_CLIENT_ID in Runner/Info.plist.");
    }
    const firebaseIosScheme = env.RTW_FIREBASE_IOS_APP_ID
      ? `app-${env.RTW_FIREBASE_IOS_APP_ID.replaceAll(":", "-")}`
      : "";
    if (firebaseIosScheme && plist.includes(`<string>${firebaseIosScheme}</string>`)) {
      add("ok", "iOS Firebase phone auth URL scheme", "Configured in Runner/Info.plist.");
    } else {
      add(
        "block",
        "iOS Firebase phone auth URL scheme",
        "Add the encoded Firebase iOS app ID URL scheme to Runner/Info.plist.",
      );
    }
  } else {
    add("block", "iOS Google URL scheme", "Missing apps/app/ios/Runner/Info.plist.");
  }

  if (existsSync(rel("apps/app/ios/Runner/Runner.entitlements"))) {
    const entitlements = readFileSync(rel("apps/app/ios/Runner/Runner.entitlements"), "utf8");
    if (entitlements.includes("com.apple.developer.applesignin")) {
      add("ok", "iOS Apple Sign In entitlement", "Configured.");
    } else {
      add("block", "iOS Apple Sign In entitlement", "Missing com.apple.developer.applesignin.");
    }
  } else {
    add("block", "iOS Apple Sign In entitlement", "Missing Runner.entitlements.");
  }

  for (const [key, value] of Object.entries(env)) {
    if (key.startsWith("RTW_") || key.startsWith("NEXT_PUBLIC_FIREBASE") || key.endsWith("_ID")) {
      flagWorkValue(key, String(value));
    }
  }
}

function checkFunctionsRuntimeEnvironment() {
  const env = loadFunctionsRuntimeEnv();
  const androidAppLinksEnabled =
    String(env.ANDROID_APP_LINKS_ENABLED ?? "true").trim().toLowerCase() !== "false";
  const requiredAppLinks = [
    "APPLE_TEAM_ID",
    "IOS_BUNDLE_ID",
    ...(androidAppLinksEnabled
      ? ["ANDROID_PACKAGE_NAME", "ANDROID_SHA256_CERT_FINGERPRINTS"]
      : []),
  ];
  const missingAppLinks = missingKeys(env, requiredAppLinks);
  if (missingAppLinks.length === 0) {
    add("ok", "Functions Universal/App Links env", "Required association values are present in Functions dotenv.");
  } else {
    add("block", "Functions Universal/App Links env", `Missing ${missingAppLinks.join(", ")}.`);
  }

  checkNonPlaceholderValue(env, "APPLE_TEAM_ID", /^(TEAMID|YOUR_|TODO|PLACEHOLDER)/i);
  checkExpectedValue(env, "IOS_BUNDLE_ID", EXPECTED_IOS_BUNDLE_ID);
  if (androidAppLinksEnabled) {
    checkExpectedValue(env, "ANDROID_PACKAGE_NAME", EXPECTED_ANDROID_PACKAGE_NAME);
    checkNonPlaceholderValue(env, "ANDROID_SHA256_CERT_FINGERPRINTS", /^(YOUR_|TODO|PLACEHOLDER)$/i);

    const fingerprints = String(env.ANDROID_SHA256_CERT_FINGERPRINTS ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
    if (fingerprints.length > 0) {
      const valid = fingerprints.every((value) => /^([A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$/.test(value));
      if (valid) {
        add("ok", "Android SHA-256 fingerprints", `${fingerprints.length} fingerprint(s).`);
      } else {
        add("block", "Android SHA-256 fingerprints", "Expected comma-separated colon-delimited SHA-256 fingerprints.");
      }
    }
  } else {
    add(
      "ok",
      "Android App Links runtime env",
      "ANDROID_APP_LINKS_ENABLED=false; assetlinks.json will return an empty array until Play signing is ready.",
    );
    if (String(env.ANDROID_PACKAGE_NAME ?? "").trim().length > 0) {
      checkExpectedValue(env, "ANDROID_PACKAGE_NAME", EXPECTED_ANDROID_PACKAGE_NAME);
    } else {
      add("warn", "ANDROID_PACKAGE_NAME", "Omitted while Android App Links are disabled.");
    }
  }

  if (String(env.MINIMUM_SCORED_RESPONSES ?? "").trim().length > 0) {
    const minimum = Number(env.MINIMUM_SCORED_RESPONSES);
    if (Number.isInteger(minimum) && minimum >= 1) {
      add("ok", "MINIMUM_SCORED_RESPONSES", String(minimum));
    } else {
      add("block", "MINIMUM_SCORED_RESPONSES", "Expected a positive integer when set.");
    }
  }

  for (const [key, value] of Object.entries(env)) {
    if (key.endsWith("_ID") || key.endsWith("_NAME") || key.endsWith("_FINGERPRINTS")) {
      flagWorkValue(key, String(value));
    }
  }
}

function printResults() {
  const icon = { ok: "OK", warn: "WARN", block: "BLOCK" };
  for (const result of results) {
    const detail = result.detail ? ` - ${result.detail}` : "";
    console.log(`[${icon[result.status]}] ${result.label}${detail}`);
  }
  const blockers = results.filter((result) => result.status === "block").length;
  const warnings = results.filter((result) => result.status === "warn").length;
  console.log();
  console.log(`Readiness result: ${blockers} blocker(s), ${warnings} warning(s).`);
  if (blockers > 0) {
    console.log("No deploy/push should run until blockers are resolved.");
    process.exit(1);
  }
}

console.log("Read the World deployment readiness check");
console.log("Read-only: this does not log in, deploy, write cloud state, or change git state.");
console.log();

checkAccounts();
checkFirebaseFiles();
checkEnvironment();
checkFunctionsRuntimeEnvironment();
printResults();
