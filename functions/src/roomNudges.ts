export const MAX_OUTGOING_ROOM_NUDGES_PER_DAY = 5;

export type RoomNudgeBlockReason =
  | "self"
  | "world"
  | "sender-not-member"
  | "target-not-member"
  | "already-answered"
  | "already-nudged"
  | "daily-limit"
  | "target-opted-out";

export function roomNudgeBlockReason(input: {
  senderUid: string;
  targetUid: string;
  isWorld: boolean;
  senderIsMember: boolean;
  targetIsMember: boolean;
  targetAnsweredToday: boolean;
  alreadyNudged: boolean;
  outgoingCount: number;
  targetAllowsNudges: boolean;
}): RoomNudgeBlockReason | null {
  if (input.senderUid === input.targetUid) return "self";
  if (input.isWorld) return "world";
  if (!input.senderIsMember) return "sender-not-member";
  if (!input.targetIsMember) return "target-not-member";
  if (input.targetAnsweredToday) return "already-answered";
  if (input.alreadyNudged) return "already-nudged";
  if (input.outgoingCount >= MAX_OUTGOING_ROOM_NUDGES_PER_DAY) {
    return "daily-limit";
  }
  if (!input.targetAllowsNudges) return "target-opted-out";
  return null;
}
