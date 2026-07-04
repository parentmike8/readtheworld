import { describe, expect, it } from "vitest";
import {
  dailyNotificationPayload,
  normalizeBroadcastAudience,
  notificationAudienceMatchesUser,
  userAllowsNotifications,
} from "../src/notifications";

describe("Daily notification payloads", () => {
  it("uses one morning room-ready payload for the daily habit", () => {
    expect(dailyNotificationPayload("daily_room_ready")).toEqual({
      title: "Read the World",
      body: "Your rooms are ready. New questions are open, and yesterday's reveal is waiting.",
      route: "/rooms",
      type: "daily_room_ready",
    });
  });

  it("keeps legacy daily question and result-ready routes distinct", () => {
    expect(dailyNotificationPayload("daily_question")).toEqual({
      title: "Read the World",
      body: "Today's question is live. Make your read before the reveal.",
      route: "/today",
      type: "daily_question",
    });
    expect(dailyNotificationPayload("result_ready")).toEqual({
      title: "Read the World",
      body: "Yesterday's result is ready. See how you read the world.",
      route: "/reveal",
      type: "result_ready",
    });
  });
});

describe("Admin notification targeting", () => {
  it("respects explicit notification opt-outs and defaults missing preference on", () => {
    expect(userAllowsNotifications({ dailyReminder: false })).toBe(false);
    expect(userAllowsNotifications({ dailyReminder: true })).toBe(true);
    expect(userAllowsNotifications({})).toBe(true);
  });

  it("normalizes unknown broadcast audiences to all", () => {
    expect(normalizeBroadcastAudience("streak_at_risk")).toBe("streak_at_risk");
    expect(normalizeBroadcastAudience("LAPSED_7D")).toBe("lapsed_7d");
    expect(normalizeBroadcastAudience("unknown")).toBe("all");
    expect(normalizeBroadcastAudience(null)).toBe("all");
  });

  it("targets readers whose streak is at risk", () => {
    expect(notificationAudienceMatchesUser(
      "streak_at_risk",
      { currentStreak: 4, lastAnsweredDailyKey: "2026-06-27" },
      "2026-06-28",
      "2026-06-21",
    )).toBe(true);
    expect(notificationAudienceMatchesUser(
      "streak_at_risk",
      { currentStreak: 4, lastAnsweredDailyKey: "2026-06-28" },
      "2026-06-28",
      "2026-06-21",
    )).toBe(false);
    expect(notificationAudienceMatchesUser(
      "streak_at_risk",
      { currentStreak: 0, lastAnsweredDailyKey: "2026-06-27" },
      "2026-06-28",
      "2026-06-21",
    )).toBe(false);
  });

  it("targets lapsed readers using lexicographic daily keys", () => {
    expect(notificationAudienceMatchesUser(
      "lapsed_7d",
      { lastAnsweredDailyKey: "2026-06-20" },
      "2026-06-28",
      "2026-06-21",
    )).toBe(true);
    expect(notificationAudienceMatchesUser(
      "lapsed_7d",
      { lastAnsweredDailyKey: "2026-06-22" },
      "2026-06-28",
      "2026-06-21",
    )).toBe(false);
    expect(notificationAudienceMatchesUser(
      "lapsed_7d",
      {},
      "2026-06-28",
      "2026-06-21",
    )).toBe(true);
  });
});
