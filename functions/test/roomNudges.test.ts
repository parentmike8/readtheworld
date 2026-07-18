import { describe, expect, it } from "vitest";

import {
  MAX_OUTGOING_ROOM_NUDGES_PER_DAY,
  roomNudgeBlockReason,
} from "../src/roomNudges";

const eligible = {
  senderUid: "sender",
  targetUid: "target",
  isWorld: false,
  senderIsMember: true,
  targetIsMember: true,
  targetAnsweredToday: false,
  alreadyNudged: false,
  outgoingCount: 0,
  targetAllowsNudges: true,
};

describe("Room nudge eligibility", () => {
  it("allows an eligible active room member", () => {
    expect(roomNudgeBlockReason(eligible)).toBeNull();
  });

  it.each([
    [{ targetUid: "sender" }, "self"],
    [{ isWorld: true }, "world"],
    [{ senderIsMember: false }, "sender-not-member"],
    [{ targetIsMember: false }, "target-not-member"],
    [{ targetAnsweredToday: true }, "already-answered"],
    [{ alreadyNudged: true }, "already-nudged"],
    [
      { outgoingCount: MAX_OUTGOING_ROOM_NUDGES_PER_DAY },
      "daily-limit",
    ],
    [{ targetAllowsNudges: false }, "target-opted-out"],
  ] as const)("blocks %s", (patch, expected) => {
    expect(roomNudgeBlockReason({ ...eligible, ...patch })).toBe(expected);
  });
});
