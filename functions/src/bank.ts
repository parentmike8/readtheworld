export type BankTier = "work-safe" | "normal" | "mature";

export const BANK_SHAPES = [
  "TASTE",
  "CONFESS",
  "MIRROR",
  "GREY",
  "TRADE",
  "NORM",
  "HABIT",
  "BELIEF",
] as const;

export type BankShape = (typeof BANK_SHAPES)[number];

export type BankQuestion = {
  id: string;
  prompt: string;
  optA: string;
  optB: string;
  tags: string[];
  tier: BankTier;
  shape: BankShape;
  active: boolean;
};

export class BankValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BankValidationError";
  }
}

export function bankTierFromFlags(workSafe: boolean, mature: boolean): BankTier {
  if (mature) return "mature";
  if (workSafe) return "work-safe";
  return "normal";
}

export function parseBooleanCell(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    return normalized === "true" || normalized === "yes" || normalized === "1";
  }
  return false;
}

export function normalizeBankShape(value: unknown): BankShape {
  const shape = typeof value === "string" ? value.trim().toUpperCase() : "";
  if ((BANK_SHAPES as readonly string[]).includes(shape)) return shape as BankShape;
  throw new BankValidationError(`Shape must be one of ${BANK_SHAPES.join(", ")}.`);
}

export function normalizeBankTags(value: unknown): string[] {
  const raw = Array.isArray(value)
    ? value
    : typeof value === "string"
      ? value.split(";")
      : [];
  const tags = raw
    .map((tag) => (typeof tag === "string" ? tag.trim() : ""))
    .filter((tag) => tag.length > 0 && tag.length <= 40);
  if (tags.length === 0) {
    throw new BankValidationError("At least one category tag is required.");
  }
  return [...new Set(tags)].slice(0, 6);
}

/** Stable id from the normalized prompt so re-imports upsert instead of duplicating. */
export function bankQuestionIdForPrompt(prompt: string): string {
  const normalized = prompt.trim().toLowerCase().replace(/\s+/g, " ");
  let hash = 0x811c9dc5;
  for (let i = 0; i < normalized.length; i++) {
    hash ^= normalized.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  let hash2 = 5381;
  for (let i = normalized.length - 1; i >= 0; i--) {
    hash2 = (Math.imul(hash2, 33) ^ normalized.charCodeAt(i)) >>> 0;
  }
  return `qb-${hash.toString(36)}${hash2.toString(36)}`;
}

function normalizeOptionLabel(value: unknown, fallback: string): string {
  const label = typeof value === "string" ? value.trim() : "";
  if (!label) return fallback;
  if (label.length > 40) {
    throw new BankValidationError("Option labels must be 40 characters or fewer.");
  }
  return label;
}

export function normalizeBankRow(row: Record<string, unknown>): BankQuestion {
  const prompt = typeof (row.prompt ?? row.question) === "string"
    ? String(row.prompt ?? row.question).trim()
    : "";
  if (prompt.length < 8 || prompt.length > 160) {
    throw new BankValidationError("Question prompt must be 8-160 characters.");
  }
  const workSafe = parseBooleanCell(row.workSafe ?? row["work safe"]);
  const mature = parseBooleanCell(row.mature);
  return {
    id: bankQuestionIdForPrompt(prompt),
    prompt,
    optA: normalizeOptionLabel(row.optA ?? row["option a"] ?? row.optionA, "Yes"),
    optB: normalizeOptionLabel(row.optB ?? row["option b"] ?? row.optionB, "No"),
    tags: normalizeBankTags(row.tags ?? row.categories),
    tier: bankTierFromFlags(workSafe, mature),
    shape: normalizeBankShape(row.shape),
    active: row.active == null ? true : parseBooleanCell(row.active),
  };
}

/**
 * Minimal CSV parser (quoted fields, embedded commas/newlines/escaped quotes)
 * for the question-bank sheet export. Returns rows of cells.
 */
export function parseCsv(text: string): string[][] {
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

/** Maps the sheet's header row to normalizeBankRow input keys. */
export function bankRowsFromCsv(text: string): Array<Record<string, unknown>> {
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
