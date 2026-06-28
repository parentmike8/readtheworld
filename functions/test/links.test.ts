import { describe, expect, it } from "vitest";
import {
  SHORT_LINK_TTL_DAYS,
  isShortLinkType,
  shortLinkExpired,
  shortLinkExpiresAt,
} from "../src/links";

describe("Short links", () => {
  it("sets explicit expirations by link type", () => {
    const createdAt = new Date("2026-06-28T12:00:00.000Z");

    expect(shortLinkExpiresAt("invite", createdAt).toISOString()).toBe(
      "2026-09-26T12:00:00.000Z",
    );
    expect(shortLinkExpiresAt("result", createdAt).toISOString()).toBe(
      "2026-07-28T12:00:00.000Z",
    );
    expect(SHORT_LINK_TTL_DAYS).toEqual({ invite: 90, result: 30 });
  });

  it("treats missing expirations as legacy active links", () => {
    expect(shortLinkExpired(null, new Date("2026-06-28T12:00:00.000Z"))).toBe(
      false,
    );
  });

  it("expires exactly at the stored expiry time", () => {
    const expiresAt = new Date("2026-07-01T00:00:00.000Z");

    expect(shortLinkExpired(expiresAt, new Date("2026-06-30T23:59:59.999Z")))
      .toBe(false);
    expect(shortLinkExpired(expiresAt, new Date("2026-07-01T00:00:00.000Z")))
      .toBe(true);
  });

  it("accepts only first-party link types", () => {
    expect(isShortLinkType("invite")).toBe(true);
    expect(isShortLinkType("result")).toBe(true);
    expect(isShortLinkType("today")).toBe(false);
  });
});
