import { describe, expect, it } from "vitest";
import { isPracticeAnswerSource } from "../src/practice";
import { resultIsRevealed } from "../src/visibility";

describe("Result visibility", () => {
  it("requires both stored results and a closed question", () => {
    expect(resultIsRevealed({
      resultExists: true,
      questionStatus: "closed",
    })).toBe(true);

    expect(resultIsRevealed({
      resultExists: true,
      questionStatus: "live",
    })).toBe(false);

    expect(resultIsRevealed({
      resultExists: false,
      questionStatus: "closed",
    })).toBe(false);
  });

  it("treats malformed or missing question status as hidden", () => {
    expect(resultIsRevealed({
      resultExists: true,
      questionStatus: null,
    })).toBe(false);

    expect(resultIsRevealed({
      resultExists: true,
      questionStatus: "archived",
    })).toBe(false);
  });
});

describe("Practice answer sources", () => {
  it("allows every non-official surface from the product plan", () => {
    expect(isPracticeAnswerSource("history-replay")).toBe(true);
    expect(isPracticeAnswerSource("archive-replay")).toBe(true);
    expect(isPracticeAnswerSource("party-replay")).toBe(true);
    expect(isPracticeAnswerSource("peek")).toBe(true);
    expect(isPracticeAnswerSource("daily")).toBe(false);
  });
});
