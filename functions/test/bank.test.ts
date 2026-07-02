import { describe, expect, it } from "vitest";
import {
  BankValidationError,
  bankQuestionIdForPrompt,
  bankRowsFromCsv,
  bankTierFromFlags,
  normalizeBankRow,
  normalizeBankTags,
  parseBooleanCell,
  parseCsv,
} from "../src/bank";

describe("bank tiers", () => {
  it("maps sheet flags to tiers", () => {
    expect(bankTierFromFlags(true, false)).toBe("work-safe");
    expect(bankTierFromFlags(false, true)).toBe("mature");
    expect(bankTierFromFlags(false, false)).toBe("normal");
    // Mature wins if a row is inconsistently flagged both ways.
    expect(bankTierFromFlags(true, true)).toBe("mature");
  });

  it("parses sheet boolean cells", () => {
    expect(parseBooleanCell("TRUE")).toBe(true);
    expect(parseBooleanCell("FALSE")).toBe(false);
    expect(parseBooleanCell(" true ")).toBe(true);
    expect(parseBooleanCell(undefined)).toBe(false);
  });
});

describe("bank ids", () => {
  it("is stable for equivalent prompts", () => {
    expect(bankQuestionIdForPrompt("Is a hot dog a sandwich?"))
      .toBe(bankQuestionIdForPrompt("  is a HOT dog a  sandwich? "));
  });

  it("differs for different prompts", () => {
    expect(bankQuestionIdForPrompt("Is a hot dog a sandwich?"))
      .not.toBe(bankQuestionIdForPrompt("Is cereal a type of soup?"));
  });
});

describe("normalizeBankRow", () => {
  const row = {
    prompt: "Is a hot dog a sandwich?",
    optA: "Yes",
    optB: "No",
    categories: "Food & Drink; Debate",
    workSafe: "TRUE",
    mature: "FALSE",
    shape: "TASTE",
  };

  it("normalizes a sheet row", () => {
    const question = normalizeBankRow(row);
    expect(question.tier).toBe("work-safe");
    expect(question.tags).toEqual(["Food & Drink", "Debate"]);
    expect(question.shape).toBe("TASTE");
    expect(question.active).toBe(true);
    expect(question.id).toMatch(/^qb-/);
  });

  it("defaults blank options to Yes/No", () => {
    const question = normalizeBankRow({ ...row, optA: "", optB: "  " });
    expect(question.optA).toBe("Yes");
    expect(question.optB).toBe("No");
  });

  it("rejects bad shapes and empty tags", () => {
    expect(() => normalizeBankRow({ ...row, shape: "SPICY" })).toThrow(BankValidationError);
    expect(() => normalizeBankRow({ ...row, categories: " ; " })).toThrow(BankValidationError);
  });

  it("dedupes tags", () => {
    expect(normalizeBankTags("Food & Drink; Food & Drink; Taste"))
      .toEqual(["Food & Drink", "Taste"]);
  });
});

describe("csv parsing", () => {
  it("handles quoted cells with commas and escaped quotes", () => {
    const rows = parseCsv('a,"b, c","say ""hi"""\nd,e,f\n');
    expect(rows).toEqual([["a", "b, c", 'say "hi"'], ["d", "e", "f"]]);
  });

  it("maps sheet headers to row records", () => {
    const csv = [
      "Question,Option A,Option B,Categories,Work Safe,Mature,Shape,Why It Works",
      'Is water wet?,Yes,No,"Science; Debate",TRUE,FALSE,TASTE,Pedantic split',
    ].join("\n");
    const rows = bankRowsFromCsv(csv);
    expect(rows).toHaveLength(1);
    const question = normalizeBankRow(rows[0]);
    expect(question.prompt).toBe("Is water wet?");
    expect(question.tags).toEqual(["Science", "Debate"]);
    expect(question.tier).toBe("work-safe");
  });
});
