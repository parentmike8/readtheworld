#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import path from "node:path";

const root = process.cwd();
const files = [
  {
    source: "apps/app/web/firebase-messaging-sw.js",
    destination: "apps/app/build/web/firebase-messaging-sw.js",
  },
];

for (const file of files) {
  const source = path.join(root, file.source);
  const destination = path.join(root, file.destination);
  if (!existsSync(source)) {
    throw new Error(`Missing static web file: ${file.source}`);
  }
  if (!existsSync(path.dirname(destination))) {
    mkdirSync(path.dirname(destination), { recursive: true });
  }
  copyFileSync(source, destination);
  readFileSync(destination, "utf8");
  console.log(`Copied ${file.source} -> ${file.destination}`);
}
