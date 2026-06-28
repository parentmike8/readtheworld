import { describe, expect, it } from "vitest";
import {
  addDaysToDailyKey,
  buildSeedQuestionSchedule,
  easternMidnightUtcForDailyKey,
} from "../src/seedQuestions";

describe("Initial seed question schedule", () => {
  it("builds launch-relative question IDs and daily windows", () => {
    const schedule = buildSeedQuestionSchedule({ startDailyKey: "2026-06-28" });

    expect(schedule).toHaveLength(7);
    expect(schedule[0]).toMatchObject({
      id: "2026-06-28-philosophy-death-date",
      status: "live",
      dailyKey: "2026-06-28",
      type: "binary",
    });
    expect(schedule[1]).toMatchObject({
      id: "2026-06-29-technology-ai-labels",
      status: "scheduled",
      dailyKey: "2026-06-29",
      type: "binary",
    });
    expect(schedule[6]).toMatchObject({
      id: "2026-07-04-choice-world-language",
      status: "scheduled",
      dailyKey: "2026-07-04",
      type: "choice",
    });
    expect(schedule[0].publishAt.toISOString()).toBe("2026-06-28T04:00:00.000Z");
    expect(schedule[0].closeAt.toISOString()).toBe("2026-06-29T04:00:00.000Z");
  });

  it("defaults to the current Eastern daily key", () => {
    const schedule = buildSeedQuestionSchedule({
      now: new Date("2026-06-28T03:59:59.000Z"),
    });

    expect(schedule[0].dailyKey).toBe("2026-06-27");
    expect(schedule[0].id).toBe("2026-06-27-philosophy-death-date");
  });

  it("uses Eastern midnight across DST boundaries", () => {
    expect(easternMidnightUtcForDailyKey("2026-03-08").toISOString()).toBe(
      "2026-03-08T05:00:00.000Z",
    );
    expect(easternMidnightUtcForDailyKey("2026-03-09").toISOString()).toBe(
      "2026-03-09T04:00:00.000Z",
    );
    expect(addDaysToDailyKey("2026-02-28", 1)).toBe("2026-03-01");
  });

  it("rejects invalid start daily keys", () => {
    expect(() => buildSeedQuestionSchedule({ startDailyKey: "07/04/2026" }))
      .toThrow(/YYYY-MM-DD/);
    expect(() => buildSeedQuestionSchedule({ startDailyKey: "2026-02-30" }))
      .toThrow(/valid calendar date/);
  });
});
