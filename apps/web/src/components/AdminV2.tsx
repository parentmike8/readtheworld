"use client";

import type { Firestore } from "firebase/firestore";
import {
  collection,
  doc,
  limit as fsLimit,
  onSnapshot,
  orderBy,
  query,
} from "firebase/firestore";
import type { Functions } from "firebase/functions";
import { httpsCallable } from "firebase/functions";
import { useEffect, useMemo, useState } from "react";

// ── shared types ────────────────────────────────────────────────────────

type BankQuestion = {
  id: string;
  prompt: string;
  optA: string;
  optB: string;
  tags: string[];
  tier: "work-safe" | "normal" | "mature";
  shape: string;
  active: boolean;
  timesUsed: number;
};

type WorldDay = {
  dailyKey: string;
  status: string;
  questions: Array<{ qid: string; prompt: string; threshold?: number }>;
  answerCount: number;
};

type RoomRow = {
  id: string;
  name: string;
  tier: string;
  memberCount: number;
  isWorld: boolean;
  createdAt: string;
};

type FlagRow = {
  id: string;
  roomName: string;
  prompt: string;
  dailyKey: string;
};

function stringOf(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function numberOf(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function useBankQuestions(firestore: Firestore | null) {
  const [questions, setQuestions] = useState<BankQuestion[]>([]);
  useEffect(() => {
    if (!firestore) return undefined;
    return onSnapshot(collection(firestore, "questionBank"), (snapshot) => {
      const rows = snapshot.docs.map((docSnap) => {
        const data = docSnap.data();
        return {
          id: docSnap.id,
          prompt: stringOf(data.prompt),
          optA: stringOf(data.optA, "Yes"),
          optB: stringOf(data.optB, "No"),
          tags: Array.isArray(data.tags) ? data.tags.map(String) : [],
          tier: (data.tier ?? "normal") as BankQuestion["tier"],
          shape: stringOf(data.shape, "TASTE"),
          active: data.active !== false,
          timesUsed: numberOf(data.timesUsed),
        };
      });
      rows.sort((a, b) => a.prompt.localeCompare(b.prompt));
      setQuestions(rows);
    });
  }, [firestore]);
  return questions;
}

// Mirrors functions/src/bank.ts parseCsv — quoted fields, escaped quotes.
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (inQuotes) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        cell += char;
      }
    } else if (char === '"') {
      inQuotes = true;
    } else if (char === ",") {
      row.push(cell);
      cell = "";
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[i + 1] === "\n") i += 1;
      row.push(cell);
      cell = "";
      if (row.some((value) => value.trim().length > 0)) rows.push(row);
      row = [];
    } else {
      cell += char;
    }
  }
  row.push(cell);
  if (row.some((value) => value.trim().length > 0)) rows.push(row);
  return rows;
}

function bankRowsFromCsv(text: string): Array<Record<string, unknown>> {
  const rows = parseCsv(text);
  if (rows.length < 2) return [];
  const headers = rows[0].map((header) => header.trim().toLowerCase());
  const keyFor = (header: string): string | null => {
    if (header === "question") return "prompt";
    if (header === "option a") return "optA";
    if (header === "option b") return "optB";
    if (header === "categories") return "categories";
    if (header === "work safe") return "workSafe";
    if (header === "mature") return "mature";
    if (header === "shape") return "shape";
    return null;
  };
  return rows.slice(1).map((cells) => {
    const record: Record<string, unknown> = {};
    headers.forEach((header, index) => {
      const key = keyFor(header);
      if (key) record[key] = cells[index] ?? "";
    });
    return record;
  });
}

const tierLabels: Record<string, string> = {
  "work-safe": "Work-safe",
  normal: "Normal",
  mature: "After Dark",
};

// ── QUESTION BANK ───────────────────────────────────────────────────────

export function QuestionBankView({
  firestore,
  functions,
  onMessage,
}: {
  firestore: Firestore | null;
  functions: Functions | null;
  onMessage: (text: string) => void;
}) {
  const questions = useBankQuestions(firestore);
  const [search, setSearch] = useState("");
  const [tierFilter, setTierFilter] = useState<string>("All");
  const [csvText, setCsvText] = useState("");
  const [importing, setImporting] = useState(false);
  const [busyId, setBusyId] = useState("");

  const filtered = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return questions.filter((question) => {
      if (tierFilter !== "All" && question.tier !== tierFilter) return false;
      if (!needle) return true;
      return (
        question.prompt.toLowerCase().includes(needle) ||
        question.tags.some((tag) => tag.toLowerCase().includes(needle))
      );
    });
  }, [questions, search, tierFilter]);

  const counts = useMemo(() => {
    const byTier: Record<string, number> = {};
    for (const question of questions) {
      byTier[question.tier] = (byTier[question.tier] ?? 0) + 1;
    }
    return byTier;
  }, [questions]);

  async function runImport() {
    if (!functions) return;
    const rows = bankRowsFromCsv(csvText);
    if (rows.length === 0) {
      onMessage("Paste a CSV export of the question sheet first (header row included).");
      return;
    }
    setImporting(true);
    try {
      let imported = 0;
      const failures: Array<{ index: number; message: string }> = [];
      const callable = httpsCallable(functions, "importQuestionBank");
      for (let index = 0; index < rows.length; index += 400) {
        const result = await callable({ rows: rows.slice(index, index + 400) });
        const data = result.data as { imported?: number; errors?: Array<{ index: number; message: string }> };
        imported += data.imported ?? 0;
        failures.push(...(data.errors ?? []));
      }
      onMessage(
        `Imported ${imported} of ${rows.length} rows.` +
          (failures.length > 0
            ? `\nSkipped ${failures.length}:\n${failures
                .slice(0, 10)
                .map((failure) => `  row ${failure.index + 2}: ${failure.message}`)
                .join("\n")}`
            : ""),
      );
      if (imported > 0) setCsvText("");
    } catch (error) {
      onMessage(String(error));
    } finally {
      setImporting(false);
    }
  }

  async function toggleActive(question: BankQuestion) {
    if (!functions) return;
    setBusyId(question.id);
    try {
      await httpsCallable(functions, "setBankQuestionActive")({
        qid: question.id,
        active: !question.active,
      });
    } catch (error) {
      onMessage(String(error));
    } finally {
      setBusyId("");
    }
  }

  return (
    <>
      <div className="adminViewHead">
        <div>
          <div className="adminKicker">v2 · Question bank</div>
          <h2 className="adminSerif">The pool rooms draw from</h2>
          <p>
            {questions.length} questions · {counts["work-safe"] ?? 0} work-safe ·{" "}
            {counts.normal ?? 0} normal · {counts.mature ?? 0} After Dark. Rooms never
            repeat a question; imports upsert by prompt.
          </p>
        </div>
      </div>

      <section className="adminEditor">
        <div className="adminViewHead compact">
          <div>
            <div className="adminKicker">Bulk import</div>
            <h2 className="adminSerif">Paste the sheet CSV</h2>
          </div>
        </div>
        <textarea
          onChange={(event) => setCsvText(event.target.value)}
          placeholder={'Question,Option A,Option B,Categories,Work Safe,Mature,Shape\n"Is a hot dog a sandwich?",Yes,No,"Food & Drink; Debate",TRUE,FALSE,TASTE'}
          rows={5}
          style={{ width: "100%", fontFamily: "var(--font-mono, monospace)", fontSize: 12 }}
          value={csvText}
        />
        <button className="adminBlueButton" disabled={importing} onClick={runImport} style={{ marginTop: 10 }}>
          {importing ? "Importing…" : "Import rows"}
        </button>
      </section>

      <div className="adminFilterPills">
        {["All", "work-safe", "normal", "mature"].map((tier) => (
          <button
            className={tierFilter === tier ? "active" : ""}
            key={tier}
            onClick={() => setTierFilter(tier)}
          >
            {tier === "All" ? "All" : tierLabels[tier]}
          </button>
        ))}
        <input
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search prompts or tags"
          style={{ flex: 1, minWidth: 180 }}
          value={search}
        />
      </div>

      <section className="adminQuestionList">
        {filtered.slice(0, 200).map((question) => (
          <div className="adminQuestionRow" key={question.id} style={{ opacity: question.active ? 1 : 0.45 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <strong>{question.prompt}</strong>
              <span>
                {question.optA} / {question.optB} · {question.tags.join(", ")} ·{" "}
                {tierLabels[question.tier]} · {question.shape} · used {question.timesUsed}×
              </span>
            </div>
            <button
              disabled={busyId === question.id}
              onClick={() => toggleActive(question)}
            >
              {question.active ? "Retire" : "Restore"}
            </button>
          </div>
        ))}
        {filtered.length > 200 ? <p>Showing first 200. Narrow the search.</p> : null}
        {filtered.length === 0 ? <p>No questions match.</p> : null}
      </section>
    </>
  );
}

// ── WORLD CURATION + UNLOCK ────────────────────────────────────────────

export function WorldCurationView({
  firestore,
  functions,
  onMessage,
}: {
  firestore: Firestore | null;
  functions: Functions | null;
  onMessage: (text: string) => void;
}) {
  const questions = useBankQuestions(firestore);
  const [worldPlayers, setWorldPlayers] = useState(0);
  const [worldGoal, setWorldGoal] = useState(5000);
  const [upcoming, setUpcoming] = useState<WorldDay[]>([]);
  const [dailyKey, setDailyKey] = useState(defaultCurationKey());
  const [picked, setPicked] = useState<Array<{ qid: string; prompt: string; threshold: number }>>([]);
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(false);
  const [unlocked, setUnlocked] = useState<boolean | null>(null);

  useEffect(() => {
    if (!firestore) return undefined;
    return onSnapshot(doc(firestore, "rooms", "world"), (snapshot) => {
      const data = snapshot.data();
      setWorldPlayers(numberOf(data?.memberCount));
      setWorldGoal(numberOf(data?.worldGoal, 5000));
    });
  }, [firestore]);

  useEffect(() => {
    if (!firestore) return undefined;
    const daysQuery = query(
      collection(firestore, "rooms", "world", "days"),
      orderBy("dailyKey", "desc"),
      fsLimit(7),
    );
    return onSnapshot(daysQuery, (snapshot) => {
      setUpcoming(
        snapshot.docs.map((docSnap) => {
          const data = docSnap.data();
          const rawQuestions = Array.isArray(data.questions) ? data.questions : [];
          return {
            dailyKey: docSnap.id,
            status: stringOf(data.status, "live"),
            answerCount: numberOf(data.answerCount),
            questions: rawQuestions.map((raw: Record<string, unknown>) => ({
              qid: stringOf(raw.qid),
              prompt: stringOf(raw.prompt),
              threshold: numberOf(raw.threshold, 1000),
            })),
          };
        }),
      );
    });
  }, [firestore]);

  useEffect(() => {
    if (!functions) return;
    httpsCallable(functions, "getAdminAppConfig")()
      .then((result) => {
        const data = result.data as { flags?: Array<{ key: string; enabled: boolean }> };
        const flag = data.flags?.find((entry) => entry.key === "feature_world_room_unlocked");
        if (flag) setUnlocked(flag.enabled);
      })
      .catch(() => setUnlocked(null));
  }, [functions]);

  const searchResults = useMemo(() => {
    const needle = search.trim().toLowerCase();
    if (!needle) return [];
    return questions
      .filter((question) => question.active && question.prompt.toLowerCase().includes(needle))
      .slice(0, 8);
  }, [questions, search]);

  async function toggleUnlock() {
    if (!functions || unlocked === null) return;
    setBusy(true);
    try {
      await httpsCallable(functions, "setAdminFeatureFlag")({
        key: "feature_world_room_unlocked",
        enabled: !unlocked,
      });
      setUnlocked(!unlocked);
      onMessage(`World predictions ${!unlocked ? "UNLOCKED" : "locked"}.`);
    } catch (error) {
      onMessage(String(error));
    } finally {
      setBusy(false);
    }
  }

  async function submitCuration() {
    if (!functions) return;
    if (picked.length !== 3) {
      onMessage("Pick exactly 3 questions for the world day.");
      return;
    }
    setBusy(true);
    try {
      const result = await httpsCallable(functions, "curateWorldDay")({
        dailyKey,
        questions: picked.map((pick) => ({ qid: pick.qid, threshold: pick.threshold })),
      });
      onMessage(JSON.stringify(result.data, null, 2));
      setPicked([]);
    } catch (error) {
      onMessage(String(error));
    } finally {
      setBusy(false);
    }
  }

  const pct = worldGoal > 0 ? Math.round((worldPlayers / worldGoal) * 100) : 0;

  return (
    <>
      <div className="adminViewHead">
        <div>
          <div className="adminKicker">v2 · The World</div>
          <h2 className="adminSerif">World room</h2>
          <p>Curate the daily 3 and control the prediction unlock.</p>
        </div>
      </div>

      <section className="adminSettingsList">
        <div className="adminSettingRow">
          <div>
            <strong>
              {worldPlayers.toLocaleString()} / {worldGoal.toLocaleString()} players ({pct}%)
            </strong>
            <span>Live count toward the unlock goal shown in the app</span>
          </div>
          <button
            className="adminBlueButton"
            disabled={busy || unlocked === null}
            onClick={toggleUnlock}
          >
            {unlocked === null
              ? "Loading…"
              : unlocked
                ? "Predictions ON. Lock them"
                : "Unlock predictions"}
          </button>
        </div>
      </section>

      <section className="adminEditor">
        <div className="adminViewHead compact">
          <div>
            <div className="adminKicker">Curate a day</div>
            <h2 className="adminSerif">{dailyKey}</h2>
          </div>
          <input
            onChange={(event) => setDailyKey(event.target.value)}
            type="date"
            value={dailyKey}
          />
        </div>
        {picked.map((pick, index) => (
          <div className="adminQuestionRow" key={pick.qid}>
            <div style={{ flex: 1 }}>
              <strong>
                {index + 1}. {pick.prompt}
              </strong>
              <span>
                Reveal threshold:{" "}
                <input
                  min={1}
                  onChange={(event) =>
                    setPicked((current) =>
                      current.map((entry) =>
                        entry.qid === pick.qid
                          ? { ...entry, threshold: Number(event.target.value) || 1000 }
                          : entry,
                      ),
                    )
                  }
                  style={{ width: 90 }}
                  type="number"
                  value={pick.threshold}
                />{" "}
                answers
              </span>
            </div>
            <button onClick={() => setPicked((current) => current.filter((entry) => entry.qid !== pick.qid))}>
              Remove
            </button>
          </div>
        ))}
        {picked.length < 3 ? (
          <>
            <input
              onChange={(event) => setSearch(event.target.value)}
              placeholder={`Search the bank to add question ${picked.length + 1} of 3`}
              style={{ width: "100%", marginTop: 8 }}
              value={search}
            />
            {searchResults.map((question) => (
              <div className="adminQuestionRow" key={question.id}>
                <div style={{ flex: 1 }}>
                  <strong>{question.prompt}</strong>
                  <span>
                    {question.optA} / {question.optB} · {tierLabels[question.tier]}
                  </span>
                </div>
                <button
                  onClick={() => {
                    setPicked((current) => [
                      ...current,
                      { qid: question.id, prompt: question.prompt, threshold: 1000 },
                    ]);
                    setSearch("");
                  }}
                >
                  Add
                </button>
              </div>
            ))}
          </>
        ) : null}
        <button
          className="adminBlueButton"
          disabled={busy || picked.length !== 3}
          onClick={submitCuration}
          style={{ marginTop: 12 }}
        >
          {busy ? "Saving…" : `Curate ${dailyKey}`}
        </button>
      </section>

      <div className="adminViewHead compact">
        <div>
          <div className="adminKicker">Recent world days</div>
        </div>
      </div>
      <section className="adminQuestionList">
        {upcoming.map((day) => (
          <div className="adminQuestionRow" key={day.dailyKey}>
            <div style={{ flex: 1 }}>
              <strong>
                {day.dailyKey} · {day.status.toUpperCase()} · {day.answerCount} locked in
              </strong>
              <span>{day.questions.map((question) => question.prompt).join(" · ")}</span>
            </div>
          </div>
        ))}
        {upcoming.length === 0 ? (
          <p>No world days yet. The rollover falls back to the bank until you curate one.</p>
        ) : null}
      </section>
    </>
  );
}

function defaultCurationKey(): string {
  const eastern = new Date().toLocaleDateString("en-CA", { timeZone: "America/New_York" });
  const [year, month, day] = eastern.split("-").map(Number);
  const next = new Date(Date.UTC(year, month - 1, day + 1));
  return next.toISOString().slice(0, 10);
}

// ── ROOMS OVERVIEW ─────────────────────────────────────────────────────

export function RoomsOverviewView({ firestore }: { firestore: Firestore | null }) {
  const [rooms, setRooms] = useState<RoomRow[]>([]);
  const [flags, setFlags] = useState<FlagRow[]>([]);

  useEffect(() => {
    if (!firestore) return undefined;
    const roomsQuery = query(
      collection(firestore, "rooms"),
      orderBy("createdAt", "desc"),
      fsLimit(30),
    );
    return onSnapshot(roomsQuery, (snapshot) => {
      setRooms(
        snapshot.docs.map((docSnap) => {
          const data = docSnap.data();
          const created = data.createdAt?.toDate?.() as Date | undefined;
          return {
            id: docSnap.id,
            name: stringOf(data.name, "Room"),
            tier: stringOf(data.tier, "normal"),
            memberCount: numberOf(data.memberCount),
            isWorld: data.isWorld === true,
            createdAt: created ? created.toISOString().slice(0, 10) : "—",
          };
        }),
      );
    });
  }, [firestore]);

  useEffect(() => {
    if (!firestore) return undefined;
    const flagsQuery = query(
      collection(firestore, "flags"),
      orderBy("createdAt", "desc"),
      fsLimit(20),
    );
    return onSnapshot(flagsQuery, (snapshot) => {
      setFlags(
        snapshot.docs.map((docSnap) => {
          const data = docSnap.data();
          return {
            id: docSnap.id,
            roomName: stringOf(data.roomName, "a room"),
            prompt: stringOf(data.prompt),
            dailyKey: stringOf(data.dailyKey),
          };
        }),
      );
    });
  }, [firestore]);

  const totalMembers = rooms
    .filter((room) => !room.isWorld)
    .reduce((sum, room) => sum + room.memberCount, 0);

  return (
    <>
      <div className="adminViewHead">
        <div>
          <div className="adminKicker">v2 · Rooms</div>
          <h2 className="adminSerif">Rooms overview</h2>
          <p>
            {rooms.filter((room) => !room.isWorld).length} recent rooms · {totalMembers}{" "}
            memberships across them · {flags.length} recent flags
          </p>
        </div>
      </div>

      <section className="adminQuestionList">
        {rooms.map((room) => (
          <div className="adminQuestionRow" key={room.id}>
            <div style={{ flex: 1 }}>
              <strong>
                {room.isWorld ? "🌍 " : ""}
                {room.name}
              </strong>
              <span>
                {room.memberCount} members · {tierLabels[room.tier] ?? room.tier} · created{" "}
                {room.createdAt}
              </span>
            </div>
          </div>
        ))}
        {rooms.length === 0 ? <p>No rooms yet.</p> : null}
      </section>

      <div className="adminViewHead compact">
        <div>
          <div className="adminKicker">Flagged custom questions</div>
        </div>
      </div>
      <section className="adminQuestionList">
        {flags.map((flag) => (
          <div className="adminQuestionRow" key={flag.id}>
            <div style={{ flex: 1 }}>
              <strong>{flag.prompt}</strong>
              <span>
                {flag.roomName} · {flag.dailyKey}
              </span>
            </div>
          </div>
        ))}
        {flags.length === 0 ? <p>No flags. Quiet so far.</p> : null}
      </section>
    </>
  );
}
