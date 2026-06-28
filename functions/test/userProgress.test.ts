import { describe, expect, it } from "vitest";
import { STARTING_READ_SCORE } from "../src/scoring";
import { missingUserProgressDefaults } from "../src/userProgress";

describe("User progress defaults", () => {
  it("initializes missing scoring fields for onboarding-created user docs", () => {
    expect(missingUserProgressDefaults({
      displayName: "Reader",
      email: "reader@example.com",
    })).toEqual({
      readScore: STARTING_READ_SCORE,
      officialQuestionsAnswered: 0,
      currentStreak: 0,
      longestStreak: 0,
    });
  });

  it("does not overwrite existing scoring fields", () => {
    expect(missingUserProgressDefaults({
      readScore: 1640,
      officialQuestionsAnswered: 12,
      currentStreak: 3,
      longestStreak: 9,
    })).toEqual({});
  });
});
