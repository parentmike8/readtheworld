import { describe, expect, it } from "vitest";
import {
  QuestionValidationError,
  normalizeDailyKey,
  normalizeQuestionOptions,
  normalizeQuestionStatus,
  parseQuestionDate,
  validateQuestionSchedule,
} from "../src/questions";

describe("Admin question validation", () => {
  it("normalizes statuses and rejects unknown states", () => {
    expect(normalizeQuestionStatus(" Scheduled ")).toBe("scheduled");
    expect(() => normalizeQuestionStatus("archived")).toThrow(QuestionValidationError);
  });

  it("normalizes option ids, labels, and duplicate detection", () => {
    expect(normalizeQuestionOptions([
      { id: " Yes Please ", label: " Yes " },
      { id: "no", label: "No" },
    ])).toEqual([
      { id: "yes-please", label: "Yes" },
      { id: "no", label: "No" },
    ]);

    expect(() => normalizeQuestionOptions([
      { id: "yes", label: "Yes" },
      { id: "yes", label: "Also yes" },
    ])).toThrow(/duplicated/);
  });

  it("validates daily keys and admin date strings", () => {
    expect(normalizeDailyKey("2026-07-03")).toBe("2026-07-03");
    expect(normalizeDailyKey("")).toBeNull();
    expect(parseQuestionDate("2026-07-03T00:00:00-04:00", "publishAt")?.toISOString())
      .toBe("2026-07-03T04:00:00.000Z");
    expect(() => normalizeDailyKey("07/03/2026")).toThrow(/YYYY-MM-DD/);
    expect(() => parseQuestionDate("not-a-date", "closeAt")).toThrow(/valid date/);
  });

  it("requires complete chronological windows before scheduling", () => {
    expect(() => validateQuestionSchedule({
      status: "draft",
      dailyKey: null,
      publishAt: null,
      closeAt: null,
    })).not.toThrow();

    expect(() => validateQuestionSchedule({
      status: "scheduled",
      dailyKey: "2026-07-03",
      publishAt: new Date("2026-07-03T04:00:00.000Z"),
      closeAt: new Date("2026-07-04T04:00:00.000Z"),
    })).not.toThrow();

    expect(() => validateQuestionSchedule({
      status: "live",
      dailyKey: "2026-07-03",
      publishAt: new Date("2026-07-04T04:00:00.000Z"),
      closeAt: new Date("2026-07-03T04:00:00.000Z"),
    })).toThrow(/after publish/);
  });
});
