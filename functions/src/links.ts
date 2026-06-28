export type ShortLinkType = "invite" | "result";

export const SHORT_LINK_TTL_DAYS: Record<ShortLinkType, number> = {
  invite: 90,
  result: 30,
};

const DAY_MS = 24 * 60 * 60 * 1000;

export function shortLinkExpiresAt(
  type: ShortLinkType,
  createdAt = new Date(),
): Date {
  return new Date(createdAt.getTime() + SHORT_LINK_TTL_DAYS[type] * DAY_MS);
}

export function shortLinkExpired(
  expiresAt: Date | null | undefined,
  now = new Date(),
): boolean {
  if (!expiresAt) return false;
  return expiresAt.getTime() <= now.getTime();
}

export function isShortLinkType(value: unknown): value is ShortLinkType {
  return value === "invite" || value === "result";
}
