#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const IOS_DEPLOYMENT_MINIMUM = 15;
const EXPECTED_BUNDLE_ID = "today.readtheworld.app";
const EXPECTED_ANDROID_PACKAGE = "today.readtheworld.app";
const EXPECTED_FIREBASE_IOS_AUTH_SCHEME = "app-1-863014025103-ios-b20d5ea02d9ec2c76bbdfa";

const results = [];

function add(status, label, detail = "") {
  results.push({ status, label, detail });
}

function rel(filePath) {
  return path.join(ROOT, filePath);
}

function run(command, args, timeoutMs = 10000) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    encoding: "utf8",
    shell: false,
    timeout: timeoutMs,
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  return {
    status: result.status ?? 1,
    signal: result.signal ?? "",
    error: result.error,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    output,
    timedOut: result.error?.code === "ETIMEDOUT" || result.signal === "SIGTERM",
  };
}

function read(filePath) {
  return readFileSync(rel(filePath), "utf8");
}

function parseVersionMajor(version) {
  const match = /(\d+)(?:\.\d+)?/.exec(version);
  return match ? Number(match[1]) : Number.NaN;
}

function checkCommand(command, args, label, timeoutMs = 10000) {
  const result = run(command, args, timeoutMs);
  if (result.timedOut) {
    add("block", label, `${command} ${args.join(" ")} timed out after ${timeoutMs}ms.`);
  } else if (result.status !== 0) {
    add("block", label, result.output || `${command} ${args.join(" ")} failed.`);
  } else {
    const firstLine = result.output.split(/\r?\n/).find(Boolean) ?? "Available.";
    add("ok", label, firstLine);
  }
  return result;
}

function checkFlutter() {
  checkCommand("flutter", ["--version"], "Flutter SDK", 15000);
}

function checkAndroid() {
  const manifestPath = "apps/app/android/app/src/main/AndroidManifest.xml";
  if (!existsSync(rel(manifestPath))) {
    add("block", "Android manifest", "Missing AndroidManifest.xml.");
    return;
  }
  const manifest = read(manifestPath);
  if (manifest.includes(`android:host="rtw.codes"`) && manifest.includes('android:autoVerify="true"')) {
    add("ok", "Android App Links", "rtw.codes autoVerify configured.");
  } else {
    add("block", "Android App Links", "Missing verified rtw.codes app-link intent filter.");
  }
  if (manifest.includes(`android:screenOrientation="portrait"`)) {
    add("ok", "Android orientation", "Portrait locked.");
  } else {
    add("block", "Android orientation", "MainActivity should be portrait locked for the source design.");
  }
  if (existsSync(rel("apps/app/android/app/build.gradle.kts"))) {
    const gradle = read("apps/app/android/app/build.gradle.kts");
    if (gradle.includes(`namespace = "${EXPECTED_ANDROID_PACKAGE}"`)) {
      add("ok", "Android package namespace", EXPECTED_ANDROID_PACKAGE);
    } else {
      add("block", "Android package namespace", `Expected ${EXPECTED_ANDROID_PACKAGE}.`);
    }
    if (gradle.includes(`applicationId = "${EXPECTED_ANDROID_PACKAGE}"`)) {
      add("ok", "Android application ID", EXPECTED_ANDROID_PACKAGE);
    } else {
      add("block", "Android application ID", `Expected ${EXPECTED_ANDROID_PACKAGE}.`);
    }
  }
}

function checkIosProjectFiles() {
  const podfilePath = "apps/app/ios/Podfile";
  const projectPath = "apps/app/ios/Runner.xcodeproj/project.pbxproj";
  let xcodeProject = "";
  if (!existsSync(rel(podfilePath))) {
    add("block", "iOS Podfile", "Missing Podfile.");
  } else {
    const podfile = read(podfilePath);
    const match = /platform\s+:ios,\s+['"](\d+(?:\.\d+)?)['"]/.exec(podfile);
    const major = match ? parseVersionMajor(match[1]) : Number.NaN;
    if (Number.isFinite(major) && major >= IOS_DEPLOYMENT_MINIMUM) {
      add("ok", "iOS Podfile deployment target", match[1]);
    } else {
      add("block", "iOS Podfile deployment target", `Expected iOS ${IOS_DEPLOYMENT_MINIMUM}.0 or newer.`);
    }
  }

  if (!existsSync(rel(projectPath))) {
    add("block", "iOS Xcode project", "Missing Runner.xcodeproj/project.pbxproj.");
  } else {
    xcodeProject = read(projectPath);
    const targets = [...xcodeProject.matchAll(/IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);/g)].map((match) => match[1]);
    const tooLow = targets.filter((target) => parseVersionMajor(target) < IOS_DEPLOYMENT_MINIMUM);
    if (targets.length > 0 && tooLow.length === 0) {
      add("ok", "iOS Xcode deployment target", targets.join(", "));
    } else {
      add("block", "iOS Xcode deployment target", `Found ${tooLow.join(", ") || "no explicit target"}; expected ${IOS_DEPLOYMENT_MINIMUM}.0 or newer.`);
    }
  }

  const plistPath = "apps/app/ios/Runner/Info.plist";
  if (existsSync(rel(plistPath))) {
    const plist = read(plistPath);
    if (plist.includes("Read the World")) {
      add("ok", "iOS display name", "Read the World.");
    } else {
      add("block", "iOS display name", "Expected Read the World.");
    }
    if (xcodeProject.includes(`PRODUCT_BUNDLE_IDENTIFIER = ${EXPECTED_BUNDLE_ID};`)) {
      add("ok", "iOS bundle identifier", EXPECTED_BUNDLE_ID);
    } else if (plist.includes(EXPECTED_BUNDLE_ID)) {
      add("ok", "iOS bundle identifier", EXPECTED_BUNDLE_ID);
    } else {
      add("block", "iOS bundle identifier", `Expected ${EXPECTED_BUNDLE_ID}.`);
    }
    if (plist.includes(`<string>${EXPECTED_FIREBASE_IOS_AUTH_SCHEME}</string>`)) {
      add("ok", "iOS Firebase phone auth URL scheme", EXPECTED_FIREBASE_IOS_AUTH_SCHEME);
    } else {
      add(
        "block",
        "iOS Firebase phone auth URL scheme",
        `Expected ${EXPECTED_FIREBASE_IOS_AUTH_SCHEME} in Runner/Info.plist.`,
      );
    }
  }

  checkCommand("plutil", ["-lint", rel("apps/app/ios/Runner/Info.plist"), rel("apps/app/ios/Runner/Runner.entitlements")], "iOS plist/entitlements", 10000);
}

function checkXcode() {
  if (process.platform !== "darwin") {
    add("warn", "Xcode", "Skipped; not running on macOS.");
    return;
  }

  checkCommand("pod", ["--version"], "CocoaPods", 10000);
  checkCommand("xcode-select", ["-p"], "Xcode developer directory", 10000);

  const firstLaunch = run("xcodebuild", ["-checkFirstLaunchStatus"], 10000);
  if (firstLaunch.timedOut) {
    add("block", "Xcode first launch", "xcodebuild -checkFirstLaunchStatus timed out.");
  } else if (firstLaunch.status === 0) {
    add("ok", "Xcode first launch", "Complete.");
  } else {
    add("block", "Xcode first launch", "Run Xcode once or run `xcodebuild -runFirstLaunch` from a healthy Xcode install.");
  }

  const sdks = run("xcodebuild", ["-showsdks"], 10000);
  if (sdks.timedOut) {
    add("block", "Xcode SDK list", "xcodebuild -showsdks timed out.");
  } else if (sdks.status !== 0) {
    add("block", "Xcode SDK list", sdks.output || "Unable to list Xcode SDKs.");
  } else {
    const hasIos = /iOS SDKs:[\s\S]*-sdk iphoneos/i.test(sdks.output);
    const hasSimulator = /iOS Simulator SDKs:[\s\S]*-sdk iphonesimulator/i.test(sdks.output);
    add(hasIos ? "ok" : "block", "iOS SDK", hasIos ? "Installed." : "Missing iOS SDK.");
    add(hasSimulator ? "ok" : "block", "iOS Simulator SDK", hasSimulator ? "Installed." : "Missing iOS Simulator SDK.");
  }

  const runtimeDirs = [
    "/Library/Developer/CoreSimulator/Profiles/Runtimes",
    path.join(process.env.HOME ?? "", "Library/Developer/CoreSimulator/Profiles/Runtimes"),
  ];
  const runtimeNames = runtimeDirs.flatMap((dir) => {
    try {
      return existsSync(dir) ? readdirSync(dir).filter((name) => /iOS.*\.simruntime$/i.test(name)) : [];
    } catch {
      return [];
    }
  });
  const simctl = run("xcrun", ["simctl", "list", "devices", "available"], 10000);
  let simctlHasDevice = false;
  if (simctl.timedOut) {
    add("block", "simctl devices", "simctl timed out while listing available devices.");
  } else if (simctl.status !== 0) {
    add("block", "simctl devices", simctl.output || "simctl failed.");
  } else if (/iPhone|iPad/.test(simctl.output)) {
    simctlHasDevice = true;
    add("ok", "simctl devices", "Available iOS simulator devices found.");
  } else {
    add("block", "simctl devices", "No available iOS simulator devices found.");
  }

  if (runtimeNames.length > 0) {
    add("ok", "iOS Simulator runtime", runtimeNames.join(", "));
  } else if (simctlHasDevice) {
    add("ok", "iOS Simulator runtime", "Available via simctl.");
  } else {
    add("block", "iOS Simulator runtime", "No iOS Simulator runtime found in CoreSimulator Profiles/Runtimes.");
  }
}

function printResults() {
  console.log("Read the World native readiness check");
  console.log("Read-only: this does not install runtimes, run first-launch tasks, build, or change cloud state.");
  console.log();

  let blocks = 0;
  let warnings = 0;
  for (const result of results) {
    const prefix = result.status === "ok" ? "[OK]" : result.status === "warn" ? "[WARN]" : "[BLOCK]";
    if (result.status === "block") blocks += 1;
    if (result.status === "warn") warnings += 1;
    console.log(`${prefix} ${result.label}${result.detail ? ` - ${result.detail}` : ""}`);
  }

  console.log();
  if (blocks > 0) {
    console.log(`Native readiness result: ${blocks} blocker(s), ${warnings} warning(s).`);
    process.exit(1);
  }
  console.log(`Native readiness result: ready (${warnings} warning(s)).`);
}

checkFlutter();
checkAndroid();
checkIosProjectFiles();
checkXcode();
printResults();
