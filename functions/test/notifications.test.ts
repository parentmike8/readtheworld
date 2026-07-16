import { describe, expect, it } from "vitest";
import {
  dailyReminderIsDue,
  dailyReminderMoment,
  dailyNotificationPayload,
  isAllowedBroadcastRoute,
  normalizeBroadcastAudience,
  notificationAudienceMatchesUser,
  selectBroadcastTokens,
  userAllowsNotifications,
} from "../src/notifications";

describe("Daily notification payloads", () => {
  it("opens Today from the daily habit reminder", () => {
    expect(dailyNotificationPayload("daily_room_ready")).toEqual({
      title: "Read the World",
      body: "Today's questions are ready. Make your read and see yesterday's results.",
      route: "/today",
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

describe("Local-time daily reminders", () => {
  it("defaults to 8 AM Eastern for profiles without the new preference", () => {
    const now = new Date("2026-07-16T12:00:00.000Z");
    expect(dailyReminderMoment({}, now)).toEqual({
      deliveryKey: "2026-07-16",
      minuteOfDay: 8 * 60,
      reminderMinutes: 8 * 60,
      timeZone: "America/New_York",
    });
    expect(dailyReminderIsDue({}, now)).toBe(true);
  });

  it("uses each profile's IANA timezone and chosen local time", () => {
    const user = {
      dailyReminderMinutes: (18 * 60) + 30,
      dailyReminderTimeZone: "America/Los_Angeles",
    };
    expect(dailyReminderIsDue(user, new Date("2026-07-17T01:30:00.000Z"))).toBe(true);
    expect(dailyReminderIsDue(user, new Date("2026-07-17T01:15:00.000Z"))).toBe(false);
  });

  it("keeps a short retry window after the selected minute", () => {
    const user = {
      dailyReminderMinutes: 8 * 60,
      dailyReminderTimeZone: "America/New_York",
    };
    expect(dailyReminderIsDue(user, new Date("2026-07-16T12:10:00.000Z"))).toBe(true);
    expect(dailyReminderIsDue(user, new Date("2026-07-16T12:15:00.000Z"))).toBe(false);
  });

  it("falls back safely when stored reminder settings are invalid", () => {
    const moment = dailyReminderMoment({
      dailyReminderMinutes: 5000,
      dailyReminderTimeZone: "Not/A_Timezone",
    }, new Date("2026-07-16T12:00:00.000Z"));
    expect(moment.reminderMinutes).toBe(8 * 60);
    expect(moment.timeZone).toBe("America/New_York");
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

describe("Broadcast route allowlist", () => {
  it("accepts exactly the routes the client router resolves", () => {
    for (const route of [
      "/today", "/reveal", "/history", "/party", "/insights",
      "/account", "/rooms",
    ]) {
      expect(isAllowedBroadcastRoute(route)).toBe(true);
    }
  });

  it("allows sub-paths only under /rooms and /join", () => {
    expect(isAllowedBroadcastRoute("/rooms/abc123")).toBe(true);
    expect(isAllowedBroadcastRoute("/rooms/abc123?edit=1")).toBe(true);
    expect(isAllowedBroadcastRoute("/join/CODE")).toBe(true);
    expect(isAllowedBroadcastRoute("/today/predict")).toBe(false);
    expect(isAllowedBroadcastRoute("/insights/weekly")).toBe(false);
  });

  it("rejects routes with no client destination (bare /join, legacy /invite)", () => {
    // Bare /join and anything under /invite fall into the app's /:code
    // catch-all or the legacy dead-end screen — a push there lands on a
    // failure page.
    expect(isAllowedBroadcastRoute("/join")).toBe(false);
    expect(isAllowedBroadcastRoute("/invite")).toBe(false);
    expect(isAllowedBroadcastRoute("/invite/CODE")).toBe(false);
  });

  it("rejects typos, unknown routes, and malformed paths", () => {
    expect(isAllowedBroadcastRoute("/todya")).toBe(false);
    expect(isAllowedBroadcastRoute("/profile")).toBe(false);
    expect(isAllowedBroadcastRoute("today")).toBe(false);
    expect(isAllowedBroadcastRoute("//evil.example")).toBe(false);
    expect(isAllowedBroadcastRoute(`/rooms/${"x".repeat(200)}`)).toBe(false);
    expect(isAllowedBroadcastRoute(null)).toBe(false);
  });
});

describe("selectBroadcastTokens", () => {
  const token = (uid: string) => ({ uid, token: `tok-${uid}` });
  const today = "2026-07-15";
  const weekAgo = "2026-07-08";

  it("filters to the audience before applying the send cap", () => {
    // Only the LAST user is lapsed; a cap-first implementation would slice
    // them away before the audience filter ever saw them.
    const tokens = [token("active1"), token("active2"), token("lapsed")];
    const userByUid = new Map<string, Record<string, unknown>>([
      ["active1", { lastAnsweredDailyKey: today }],
      ["active2", { lastAnsweredDailyKey: today }],
      ["lapsed", { lastAnsweredDailyKey: "2026-06-01" }],
    ]);
    const selected = selectBroadcastTokens({
      tokens,
      audience: "lapsed_7d",
      userByUid,
      limit: 2,
      todayDailyKey: today,
      sevenDaysAgoDailyKey: weekAgo,
    });
    expect(selected).toEqual([token("lapsed")]);
  });

  it("caps the matched audience at the limit", () => {
    const tokens = [token("a"), token("b"), token("c")];
    const selected = selectBroadcastTokens({
      tokens,
      audience: "all",
      userByUid: new Map(),
      limit: 2,
      todayDailyKey: today,
      sevenDaysAgoDailyKey: weekAgo,
    });
    expect(selected).toEqual([token("a"), token("b")]);
  });

  it("clamps a nonsense limit to at least one send", () => {
    const tokens = [token("a"), token("b")];
    const selected = selectBroadcastTokens({
      tokens,
      audience: "all",
      userByUid: new Map(),
      limit: -5,
      todayDailyKey: today,
      sevenDaysAgoDailyKey: weekAgo,
    });
    expect(selected).toEqual([token("a")]);
  });
});
