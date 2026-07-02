#!/usr/bin/env node
// QA-only: shift every live room day back one day in the EMULATOR so the
// real rolloverRooms close/assign path can run as if it were tomorrow.
import { createRequire } from "module";
const requireFromFunctions = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp } = requireFromFunctions("firebase-admin/app");
const { getFirestore } = requireFromFunctions("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Emulator-only script. Set FIRESTORE_EMULATOR_HOST.");
  process.exit(1);
}
initializeApp({ projectId: "read-the-world-74f2a" });
const db = getFirestore();

function shiftKey(dailyKey, days) {
  const [year, month, day] = dailyKey.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return date.toISOString().slice(0, 10);
}

const rooms = await db.collection("rooms").get();
for (const room of rooms.docs) {
  const days = await room.ref.collection("days").where("status", "==", "live").get();
  for (const day of days.docs) {
    const newKey = shiftKey(day.id, -1);
    const newRef = room.ref.collection("days").doc(newKey);
    await newRef.set({ ...day.data(), dailyKey: newKey });
    const answers = await day.ref.collection("answers").get();
    for (const answer of answers.docs) {
      await newRef.collection("answers").doc(answer.id).set(answer.data());
      await answer.ref.delete();
    }
    await day.ref.delete();
    await room.ref.set({ currentDailyKey: newKey }, { merge: true });
    console.log(`${room.id}: ${day.id} -> ${newKey}`);
  }
  // Members' lastPlayedDailyKey shifts too so streak math stays coherent.
  const members = await room.ref.collection("members").get();
  for (const member of members.docs) {
    const lastPlayed = member.data().lastPlayedDailyKey;
    if (typeof lastPlayed === "string") {
      await member.ref.set({ lastPlayedDailyKey: shiftKey(lastPlayed, -1) }, { merge: true });
    }
  }
}
console.log("Time travel complete.");
