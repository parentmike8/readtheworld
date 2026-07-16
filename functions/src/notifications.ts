export type BroadcastAudience = "all" | "streak_at_risk" | "lapsed_7d";
export type DailyNotificationKind = "daily_room_ready" | "daily_question" | "result_ready";

export type DailyNotificationPayload = {
  title: string;
  body: string;
  route: string;
  type: DailyNotificationKind;
};

const BROADCAST_AUDIENCES: BroadcastAudience[] = ["all", "streak_at_risk", "lapsed_7d"];

/**
 * Mirror of the client tap-router allowlist, narrowed to routes the router
 * actually resolves: bare "/join" and anything under "/invite" fall into the
 * client's /:code catch-all (or the legacy dead-end screen) and would ship a
 * push that lands on a failure page. /rooms and /join accept sub-paths;
 * everything else must match exactly.
 */
const BROADCAST_EXACT_ROUTES = [
  "/today",
  "/reveal",
  "/history",
  "/party",
  "/insights",
  "/account",
  "/rooms",
];
const BROADCAST_SUBPATH_ROUTES = ["/rooms", "/join"];

export function isAllowedBroadcastRoute(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const route = value.trim();
  if (!route.startsWith("/") || route.startsWith("//") || route.length > 120) {
    return false;
  }
  if (BROADCAST_EXACT_ROUTES.includes(route)) return true;
  return BROADCAST_SUBPATH_ROUTES.some((prefix) => route.startsWith(`${prefix}/`));
}

/**
 * Pick the tokens for a broadcast: audience filter FIRST, then the send cap.
 * Applying the cap first would silently drop eligible users as soon as total
 * tokens exceed the limit.
 */
export function selectBroadcastTokens<T extends { uid: string }>(input: {
  tokens: T[];
  audience: BroadcastAudience;
  userByUid: Map<string, Record<string, unknown>>;
  limit: number;
  todayDailyKey: string;
  sevenDaysAgoDailyKey: string;
}): T[] {
  const cap = Math.max(1, Math.floor(input.limit));
  const matched = input.audience === "all"
    ? input.tokens
    : input.tokens.filter((token) => notificationAudienceMatchesUser(
      input.audience,
      input.userByUid.get(token.uid) ?? {},
      input.todayDailyKey,
      input.sevenDaysAgoDailyKey,
    ));
  return matched.slice(0, cap);
}

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
  if (kind === "daily_room_ready") {
    return {
      title: "Read the World",
      body: "Your rooms are ready. New questions are open, and yesterday's reveal is waiting.",
      route: "/rooms",
      type: "daily_room_ready",
    };
  }

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
