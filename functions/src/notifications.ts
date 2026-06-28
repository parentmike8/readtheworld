export type BroadcastAudience = "all" | "streak_at_risk" | "lapsed_7d";
export type DailyNotificationKind = "daily_question" | "result_ready";

export type DailyNotificationPayload = {
  title: string;
  body: string;
  route: string;
  type: DailyNotificationKind;
};

const BROADCAST_AUDIENCES: BroadcastAudience[] = ["all", "streak_at_risk", "lapsed_7d"];

export function normalizeBroadcastAudience(value: unknown): BroadcastAudience {
  const audience = typeof value === "string" ? value.trim().toLowerCase() : "all";
  return BROADCAST_AUDIENCES.includes(audience as BroadcastAudience)
    ? audience as BroadcastAudience
    : "all";
}

export function notificationAudienceMatchesUser(
  audience: BroadcastAudience,
  user: Record<string, unknown>,
  todayDailyKey: string,
  sevenDaysAgoDailyKey: string,
): boolean {
  if (audience === "all") return true;
  const lastAnsweredDailyKey =
    typeof user.lastAnsweredDailyKey === "string" ? user.lastAnsweredDailyKey : "";
  if (audience === "streak_at_risk") {
    return Number(user.currentStreak ?? 0) > 0 && lastAnsweredDailyKey !== todayDailyKey;
  }
  return lastAnsweredDailyKey.length === 0 || lastAnsweredDailyKey < sevenDaysAgoDailyKey;
}

export function userAllowsNotifications(user: Record<string, unknown>): boolean {
  return user.dailyReminder !== false;
}

export function dailyNotificationPayload(kind: DailyNotificationKind): DailyNotificationPayload {
  if (kind === "result_ready") {
    return {
      title: "Read the World",
      body: "Yesterday's result is ready. See how you read the world.",
      route: "/reveal",
      type: "result_ready",
    };
  }

  return {
    title: "Read the World",
    body: "Today's question is live. Make your read before the reveal.",
    route: "/today",
    type: "daily_question",
  };
}
