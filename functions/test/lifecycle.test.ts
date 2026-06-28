import { describe, expect, it } from "vitest";
import { decideDailyOpen } from "../src/lifecycle";

describe("Daily lifecycle open decision", () => {
  it("opens the next scheduled question when no live question remains", () => {
    expect(decideDailyOpen([], ["q2", "q3"])).toEqual({
      openQuestionId: "q2",
      skipReason: null,
    });
  });

  it("does not open a scheduled question while a live question remains", () => {
    expect(decideDailyOpen(["q1"], ["q2"])).toEqual({
      openQuestionId: null,
      skipReason: "live-question-still-open",
    });
  });

  it("does nothing when there is no scheduled question ready", () => {
    expect(decideDailyOpen([], [])).toEqual({
      openQuestionId: null,
      skipReason: "no-scheduled-question",
    });
  });
});
