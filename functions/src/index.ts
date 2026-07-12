import { createHash, randomBytes } from "crypto";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall, onRequest, type Request } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getMessaging } from "firebase-admin/messaging";
import { getRemoteConfig } from "firebase-admin/remote-config";
import {
  FieldPath,
  FieldValue,
  type DocumentReference,
  type DocumentData,
  type Query,
  type QueryDocumentSnapshot,
  WriteBatch,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {
  EASTERN_TIME_ZONE,
  STARTING_READ_SCORE,
  averagePredictionBiasLabel,
  calculatePredictionBias,
  calculateReadAccuracy,
  dailyPercentilesByAccuracy,
  dailyKeyForEasternDate,
  nextStreakForDailyKey,
  rankedLeaderboardRows,
  readScorePercentileFromRank,
  scoreDeltaForPercentile,
  smoothedCategoryScore,
  type LeaderboardInput,
} from "./scoring";
import { addDaysToDailyKey, buildProductionQuestionSeed } from "./seedQuestions";
import {
  isShortLinkType,
  shortLinkExpired,
  shortLinkExpiresAt,
  type ShortLinkType,
} from "./links";
import { decideDailyOpen } from "./lifecycle";
import {
  CUSTOM_QUEUE_CAP_PER_MEMBER,
  ROOM_QUESTIONS_PER_DAY,
  ROOM_STARTING_SCORE,
  RoomValidationError,
  WORLD_PLAYER_GOAL,
  WORLD_ROOM_ID,
  customInjectionCount,
  hasClearlyObjectionableContent,
  normalizeCustomOption,
  normalizeCustomQuestionText,
  normalizePrediction,
  normalizeRoomCats,
  normalizeRoomColor,
  normalizeRoomName,
  normalizeRoomTier,
  roomDailyScoreDeltas,
  roomRolloverPlan,
  scoreWorldQuestion,
  selectDailyQuestions,
  tierAllowsQuestion,
  type CandidateQuestion,
  type RoomMemberDayResult,
  type WorldPredictorInput,
} from "./rooms";
import {
  BankValidationError,
  bankQuestionIdForPrompt,
  normalizeBankRow,
  type BankShape,
  type BankTier,
} from "./bank";
import {
  QuestionValidationError,
  normalizeDailyKey,
  normalizeQuestionOptions,
  normalizeQuestionStatus,
  parseQuestionDate,
  validateQuestionSchedule,
  type QuestionStatus,
} from "./questions";
import {
  dailyNotificationPayload,
  normalizeBroadcastAudience,
  notificationAudienceMatchesUser,
  userAllowsNotifications,
  type BroadcastAudience,
} from "./notifications";
import {
  dailyHabitEmail,
  feedbackEmail,
  isValidEmail,
  memberJoinedEmail,
  newUserEmail,
  PostmarkSendError,
  postmarkServerToken,
  sendPostmarkEmail,
  supportContactEmail,
  verificationEmail,
} from "./email";
import {
  ADMIN_FEATURE_FLAGS,
  adminFeatureFlagDefinition,
  remoteConfigBooleanValue,
  remoteConfigParameterBooleanValue,
  type AdminFeatureFlagKey,
} from "./config";
import { resultIsRevealed } from "./visibility";
import { isPracticeAnswerSource } from "./practice";
import { missingUserProgressDefaults } from "./userProgress";

initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 20 });

const db = getFirestore();
const SHORT_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const COUNTER_SHARDS = 20;
const LEADERBOARD_LIMIT = 100;
const FIRESTORE_BATCH_LIMIT = 450;
const MAX_FCM_TOKENS_PER_SEND = 500;
const FEATURE_FLAG_CACHE_MS = 60 * 1000;
const APP_URL = "https://app.readtheworld.today";
const MARKETING_URL = "https://readtheworld.today";
const SHARE_URL = `${MARKETING_URL}/share`;
const ALLOWED_ADMIN_EMAIL = "mike@readtheworld.today";
const AUTH_HANDOFF_TTL_MS = 5 * 60 * 1000;
const FEEDBACK_COOLDOWN_MS = 60 * 1000;
const SUPPORT_CONTACT_COOLDOWN_MS = 60 * 1000;
const CUSTOM_QUESTION_TERMS_VERSION = "2026-07-11";
const CONTENT_REPORT_RESPONSE_MS = 24 * 60 * 60 * 1000;
// App Check is enforced in production; the emulator has no tokens.
const callableOptions = { enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true" };
const authOnlyCallableOptions = callableOptions;
const emailCallableOptions = {
  ...callableOptions,
  secrets: [postmarkServerToken],
};
const feedbackCallableOptions = {
  ...callableOptions,
  secrets: [postmarkServerToken],
};
// Account deletion must remain available to every authenticated user even if
// App Check has not finished refreshing immediately after a new sign-in. The
// handler still scopes all work to request.auth.uid.
const accountDeletionCallableOptions = { enforceAppCheck: false };

class ShortCodeCollisionError extends Error {}

type QuestionOption = {
  id: string;
  label: string;
};

type Question = {
  category: string;
  prompt: string;
  options: QuestionOption[];
  status: QuestionStatus;
  dailyKey?: string;
  publishAt?: Timestamp;
  closeAt?: Timestamp;
};

type OfficialAnswer = {
  uid: string;
  refPath: string;
  questionId: string;
  selectedOptionId: string;
  predictedShare: number;
  source: string;
};

type NotificationToken = {
  uid: string;
  refPath: string;
  token: string;
};

type NotificationPayload = {
  title: string;
  body: string;
  route: string;
  type: string;
};

type AuthHandoffPayload = {
  uid: string;
  questionId: string | null;
  selectedOptionId: string | null;
  predictedShare: number | null;
  targetRoute: string;
};

let featureFlagCache:
  | {
      expiresAt: number;
      values: Map<AdminFeatureFlagKey, boolean>;
    }
  | null = null;

type AdminQuestionSummary = {
  id: string;
  prompt: string;
  category: string;
  status: string;
  dailyKey: string;
  publishAt: string | null;
  closeAt: string | null;
  options: QuestionOption[];
};

type AdminResultSummary = {
  questionId: string;
  prompt: string;
  category: string;
  dailyKey: string;
  status: string;
  options: QuestionOption[];
  totalAnswers: number;
  optionCounts: Record<string, number>;
  optionPcts: Record<string, number>;
  countedTowardScore: boolean;
  closedAt: string | null;
  avgPredictedShare: number | null;
  medianReadAccuracy: number | null;
  highAccuracyPct: number | null;
  accuracyBuckets: Record<string, number>;
};

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in is required.");
  }
  return auth.uid;
}

async function requireAdmin(uid: string): Promise<void> {
  const user = await getAuth().getUser(uid);
  const allowedGoogleAdmin =
    user.email?.toLowerCase() === ALLOWED_ADMIN_EMAIL &&
    user.emailVerified === true &&
    user.providerData.some((provider) => provider.providerId === "google.com");
  if (user.customClaims?.admin !== true && !allowedGoogleAdmin) {
    throw new HttpsError("permission-denied", "Admin access is required.");
  }
}

async function assertNoOtherLiveQuestion(questionId: string): Promise<void> {
  const liveSnap = await db
    .collection("questions")
    .where("status", "==", "live")
    .limit(5)
    .get();
  const otherLiveQuestionIds = liveSnap.docs
    .map((doc) => doc.id)
    .filter((id) => id !== questionId);
  if (otherLiveQuestionIds.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      "A live question already exists. Close it before making another question live.",
    );
  }
}

function assertString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function assertQuestionReactionId(value: unknown): string {
  const qid = assertString(value, "qid");
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(qid)) {
    throw new HttpsError("invalid-argument", "qid is invalid.");
  }
  return qid;
}

function assertFeedbackMessage(value: unknown): string {
  const message = assertString(value, "feedback");
  if (message.length < 2) {
    throw new HttpsError("invalid-argument", "Write a little feedback first.");
  }
  if (message.length > 4000) {
    throw new HttpsError("invalid-argument", "Feedback must be 4000 characters or fewer.");
  }
  return message;
}

function normalizeFeedbackSource(value: unknown): string {
  if (typeof value !== "string") return "profile";
  const source = value.trim().toLowerCase();
  if (!/^[a-z0-9_-]{1,40}$/.test(source)) return "profile";
  return source;
}

function timestampToIso(value: unknown): string {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string" && value.trim().length > 0) return value.trim();
  return new Date().toISOString();
}

function assertPrediction(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 100) {
    throw new HttpsError(
      "invalid-argument",
      "predictedShare must be an integer from 0 to 100.",
    );
  }
  return value;
}

function normalizeEmail(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "email is required.");
  }
  const email = value.trim().toLowerCase();
  const valid =
    email.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) &&
    !email.includes("..");
  if (!valid) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function assertSupportName(value: unknown): string {
  const name = assertString(value, "name");
  if (name.length > 120) {
    throw new HttpsError("invalid-argument", "Name must be 120 characters or fewer.");
  }
  return name;
}

function assertSupportMessage(value: unknown): string {
  const message = assertString(value, "message");
  if (message.length < 4) {
    throw new HttpsError("invalid-argument", "Write a little more detail first.");
  }
  if (message.length > 4000) {
    throw new HttpsError("invalid-argument", "Message must be 4000 characters or fewer.");
  }
  return message;
}

function requestIpHash(req: Request): string {
  const forwarded = req.header("x-forwarded-for") ?? "";
  const ip = forwarded.split(",")[0]?.trim() || req.ip || "unknown";
  return createHash("sha256").update(ip).digest("hex");
}

function assertNotificationText(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  const text = assertString(value, field);
  if (text.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} must be ${maxLength} characters or fewer.`);
  }
  return text;
}

function assertNotificationRoute(value: unknown): string {
  const route = assertString(value ?? "/today", "route");
  if (!route.startsWith("/") || route.startsWith("//") || route.length > 120) {
    throw new HttpsError("invalid-argument", "route must be a relative app path.");
  }
  return route;
}

function assertAppRoute(value: unknown, fallback = "/today"): string {
  const route = assertNotificationRoute(value ?? fallback);
  if (![
    "/auth",
    "/onboarding",
    "/today",
    "/today/predict",
    "/today/locked",
    "/history",
    "/insights",
    "/account",
    "/rooms",
    "/join",
    "/party",
    "/profile",
  ].some((path) => route === path || route.startsWith(`${path}/`))) {
    throw new HttpsError("invalid-argument", "targetRoute is not an allowed app path.");
  }
  return route;
}

async function appFeatureEnabled(key: AdminFeatureFlagKey): Promise<boolean> {
  const definition = adminFeatureFlagDefinition(key);
  if (!definition) return true;
  const now = Date.now();
  if (featureFlagCache != null && featureFlagCache.expiresAt > now) {
    return featureFlagCache.values.get(key) ?? definition.defaultValue;
  }

  const values = new Map<AdminFeatureFlagKey, boolean>(
    ADMIN_FEATURE_FLAGS.map((flag) => [flag.key, flag.defaultValue]),
  );
  try {
    const template = await getRemoteConfig().getTemplate();
    for (const flag of ADMIN_FEATURE_FLAGS) {
      values.set(
        flag.key,
        remoteConfigParameterBooleanValue(
          template.parameters[flag.key],
          flag.defaultValue,
        ),
      );
    }
  } catch (error) {
    logger.warn("Remote Config feature flag check failed; using defaults", {
      key,
      error: String(error),
    });
  }

  featureFlagCache = {
    expiresAt: now + FEATURE_FLAG_CACHE_MS,
    values,
  };
  return values.get(key) ?? definition.defaultValue;
}

async function requireAppFeature(
  key: AdminFeatureFlagKey,
  message: string,
): Promise<void> {
  if (!(await appFeatureEnabled(key))) {
    throw new HttpsError("failed-precondition", message);
  }
}

async function shortLinkFeatureEnabled(type: ShortLinkType): Promise<boolean> {
  if (type === "room") return true; // Rooms are core in v2 — no flag.
  if (type === "invite") return appFeatureEnabled("feature_friends");
  return appFeatureEnabled("feature_result_sharing");
}

function mapQuestionValidationError(error: unknown): never {
  if (error instanceof QuestionValidationError) {
    throw new HttpsError("invalid-argument", error.message);
  }
  throw error;
}

function waitlistDocId(email: string): string {
  return createHash("sha256").update(email).digest("hex");
}

function optionLabels(question: Question): Record<string, string> {
  return Object.fromEntries(question.options.map((option) => [option.id, option.label]));
}

function randomCode(length = 7): string {
  const bytes = randomBytes(length);
  return Array.from(bytes)
    .map((byte) => SHORT_CODE_ALPHABET[byte % SHORT_CODE_ALPHABET.length])
    .join("");
}

type ShortLinkCreateInput = {
  type: ShortLinkType;
  targetId: string;
  createdBy: string;
  createInviteDoc?: boolean;
};

async function createShortLink(input: ShortLinkCreateInput): Promise<{
  code: string;
  expiresAt: Timestamp;
}> {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = randomCode();
    const expiresAt = expiresAtTimestamp(input.type);
    try {
      await db.runTransaction(async (tx) => {
        const linkRef = db.collection("links").doc(code);
        const linkSnap = await tx.get(linkRef);
        if (linkSnap.exists) throw new ShortCodeCollisionError();
        tx.create(linkRef, {
          type: input.type,
          targetId: input.targetId,
          createdBy: input.createdBy,
          expiresAt,
          createdAt: FieldValue.serverTimestamp(),
          counters: { opens: 0 },
        });
        if (input.createInviteDoc === true) {
          tx.create(db.collection("invites").doc(code), {
            createdBy: input.createdBy,
            expiresAt,
            createdAt: FieldValue.serverTimestamp(),
            status: "active",
          });
        }
      });
      return { code, expiresAt };
    } catch (error) {
      if (error instanceof ShortCodeCollisionError) continue;
      throw error;
    }
  }
  throw new HttpsError("resource-exhausted", "Could not reserve a short code.");
}

async function createAuthHandoffDocument(input: AuthHandoffPayload): Promise<string> {
  const expiresAt = Timestamp.fromMillis(Date.now() + AUTH_HANDOFF_TTL_MS);
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = randomCode(12);
    try {
      await db.runTransaction(async (tx) => {
        const ref = db.collection("authHandoffs").doc(code);
        const snap = await tx.get(ref);
        if (snap.exists) throw new ShortCodeCollisionError();
        tx.create(ref, {
          ...input,
          status: "active",
          expiresAt,
          createdAt: FieldValue.serverTimestamp(),
        });
      });
      return code;
    } catch (error) {
      if (error instanceof ShortCodeCollisionError) continue;
      throw error;
    }
  }
  throw new HttpsError("resource-exhausted", "Could not reserve an auth handoff.");
}

function expiresAtTimestamp(type: ShortLinkType): Timestamp {
  return Timestamp.fromDate(shortLinkExpiresAt(type));
}

async function readRevealState(questionId: string): Promise<{
  revealed: boolean;
  result: Record<string, unknown>;
}> {
  const [resultSnap, questionSnap] = await Promise.all([
    db.collection("dailyResults").doc(questionId).get(),
    db.collection("questions").doc(questionId).get(),
  ]);
  const questionStatus = questionSnap.exists
    ? String(questionSnap.data()?.status ?? "")
    : null;

  return {
    revealed: resultIsRevealed({
      resultExists: resultSnap.exists,
      questionStatus,
    }),
    result: (resultSnap.data() ?? {}) as Record<string, unknown>,
  };
}

async function requireRevealedResult(
  questionId: string,
  message = "Only revealed results are available.",
): Promise<Record<string, unknown>> {
  const state = await readRevealState(questionId);
  if (!state.revealed) {
    throw new HttpsError("failed-precondition", message);
  }
  return state.result;
}

function timestampDate(value: unknown): Date | null {
  return value instanceof Timestamp ? value.toDate() : null;
}

function shardId(): string {
  return String(Math.floor(Math.random() * COUNTER_SHARDS)).padStart(2, "0");
}

function timestampMillis(value?: Timestamp): number | null {
  return value ? value.toMillis() : null;
}

function timestampIso(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function hasCompletedDemographics(data: Record<string, unknown> | undefined): boolean {
  const demographics = data?.demographics;
  if (!demographics || typeof demographics !== "object") return false;
  const fields = demographics as Record<string, unknown>;
  return typeof fields.birthdate === "string" &&
    fields.birthdate.trim().length > 0 &&
    typeof fields.gender === "string" &&
    fields.gender.trim().length > 0 &&
    typeof fields.country === "string" &&
    fields.country.trim().length > 0;
}

function numericRecord(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object") return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .map(([key, recordValue]) => [key, Number(recordValue ?? 0)])
      .filter(([, recordValue]) => Number.isFinite(recordValue)),
  );
}

function chunkArray<T>(values: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

async function commitBatchedWrites(
  writes: Array<(batch: WriteBatch) => void>,
): Promise<void> {
  for (const chunk of chunkArray(writes, FIRESTORE_BATCH_LIMIT)) {
    const batch = db.batch();
    for (const write of chunk) write(batch);
    await batch.commit();
  }
}

async function deleteUserSubcollection(uid: string, collectionId: string): Promise<number> {
  let deleted = 0;
  while (true) {
    const snapshot = await db
      .collection("users")
      .doc(uid)
      .collection(collectionId)
      .limit(FIRESTORE_BATCH_LIMIT)
      .get();
    if (snapshot.empty) return deleted;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snapshot.size;
    if (snapshot.size < FIRESTORE_BATCH_LIMIT) return deleted;
  }
}

async function refsForQuery(query: Query): Promise<DocumentReference[]> {
  const snapshot = await query.get();
  return snapshot.docs.map((doc) => doc.ref);
}

function uniqueRefs(refs: DocumentReference[]): DocumentReference[] {
  const seen = new Set<string>();
  const unique: DocumentReference[] = [];
  for (const ref of refs) {
    if (seen.has(ref.path)) continue;
    seen.add(ref.path);
    unique.push(ref);
  }
  return unique;
}

async function clearServerOwnedShareData(uid: string): Promise<{
  links: number;
  invitesCreated: number;
  invitesAcceptedUpdated: number;
}> {
  const [
    createdLinkRefs,
    targetedLinkRefs,
    createdInviteRefs,
    acceptedInviteRefs,
  ] = await Promise.all([
    refsForQuery(db.collection("links").where("createdBy", "==", uid)),
    refsForQuery(db.collection("links").where("targetId", "==", uid)),
    refsForQuery(db.collection("invites").where("createdBy", "==", uid)),
    refsForQuery(db.collection("invites").where("acceptedBy", "array-contains", uid)),
  ]);

  const linkRefs = uniqueRefs([...createdLinkRefs, ...targetedLinkRefs]);
  const createdInvitePaths = new Set(createdInviteRefs.map((ref) => ref.path));
  const acceptedOnlyInviteRefs = acceptedInviteRefs.filter(
    (ref) => !createdInvitePaths.has(ref.path),
  );
  const writes: Array<(batch: WriteBatch) => void> = [];

  for (const ref of linkRefs) {
    writes.push((batch) => batch.delete(ref));
  }
  for (const ref of createdInviteRefs) {
    writes.push((batch) => batch.delete(ref));
  }
  for (const ref of acceptedOnlyInviteRefs) {
    writes.push((batch) => batch.set(ref, {
      acceptedBy: FieldValue.arrayRemove(uid),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }

  if (writes.length > 0) {
    await commitBatchedWrites(writes);
  }

  return {
    links: linkRefs.length,
    invitesCreated: createdInviteRefs.length,
    invitesAcceptedUpdated: acceptedOnlyInviteRefs.length,
  };
}

async function recomputeGlobalLeaderboard(limit = LEADERBOARD_LIMIT): Promise<{
  rows: number;
}> {
  const usersSnap = await db
    .collection("users")
    .where("officialQuestionsAnswered", ">", 0)
    .limit(1000)
    .get();

  const inputs: LeaderboardInput[] = usersSnap.docs.map((doc) => {
    const data = doc.data();
    return {
      uid: doc.id,
      displayName: String(data.displayName ?? ""),
      avatarColor: String(data.avatarColor ?? "blue"),
      readScore: Number(data.readScore ?? STARTING_READ_SCORE),
      officialQuestionsAnswered: Number(data.officialQuestionsAnswered ?? 0),
      currentStreak: Number(data.currentStreak ?? 0),
    };
  });
  const allRows = rankedLeaderboardRows(inputs, inputs.length);
  const rows = allRows.slice(0, limit);
  const boardRef = db.collection("leaderboards").doc("global");
  const writes: Array<(batch: WriteBatch) => void> = [
    (batch) => batch.set(boardRef, {
      boardId: "global",
      rows: rows.length,
      eligibleUsers: allRows.length,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }),
  ];
  for (const row of rows) {
    writes.push((batch) => batch.set(boardRef.collection("rows").doc(row.uid), {
      ...row,
      readScorePercentile: readScorePercentileFromRank(row.rank, allRows.length),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }
  for (const row of allRows) {
    writes.push((batch) => batch.set(db.collection("users").doc(row.uid), {
      leaderboardRank: row.rank,
      readScorePercentile: readScorePercentileFromRank(row.rank, allRows.length),
      leaderboardUpdatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }
  await commitBatchedWrites(writes);
  for (const row of allRows) {
    await fanOutFriendProfile(row);
  }
  return { rows: rows.length };
}

async function activeNotificationTokens(): Promise<NotificationToken[]> {
  const snap = await db
    .collectionGroup("notificationTokens")
    .where("enabled", "==", true)
    .get();
  const tokens = snap.docs
    .map((doc) => ({
      uid: doc.ref.parent.parent?.id ?? "",
      refPath: doc.ref.path,
      token: String(doc.data().token ?? ""),
    }))
    .filter((token) => token.uid.length > 0 && token.token.length > 0);
  if (tokens.length === 0) return [];

  const userRefs = [...new Set(tokens.map((token) => token.uid))]
    .map((uid) => db.collection("users").doc(uid));
  const userByUid = new Map<string, Record<string, unknown>>();
  for (const chunk of chunkArray(userRefs, 100)) {
    const userSnaps = await db.getAll(...chunk);
    for (const snap of userSnaps) {
      userByUid.set(snap.id, snap.data() ?? {});
    }
  }

  return tokens.filter((token) => userAllowsNotifications(
    userByUid.get(token.uid) ?? {},
  ));
}

async function notificationTokensForAudience(
  audience: BroadcastAudience,
  limit: number,
): Promise<NotificationToken[]> {
  const tokens = (await activeNotificationTokens()).slice(0, Math.max(1, limit));
  if (audience === "all" || tokens.length === 0) return tokens;

  const today = new Date();
  const todayDailyKey = dailyKeyForEasternDate(today);
  const sevenDaysAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
  const sevenDaysAgoDailyKey = dailyKeyForEasternDate(sevenDaysAgo);
  const userRefs = [...new Set(tokens.map((token) => token.uid))]
    .map((uid) => db.collection("users").doc(uid));
  const userByUid = new Map<string, Record<string, unknown>>();
  for (const chunk of chunkArray(userRefs, 100)) {
    const userSnaps = await db.getAll(...chunk);
    for (const snap of userSnaps) {
      userByUid.set(snap.id, snap.data() ?? {});
    }
  }

  return tokens.filter((token) => notificationAudienceMatchesUser(
    audience,
    userByUid.get(token.uid) ?? {},
    todayDailyKey,
    sevenDaysAgoDailyKey,
  ));
}

async function friendProfileFields(uid: string, authDisplayName?: string | null): Promise<Record<string, unknown>> {
  const userSnap = await db.collection("users").doc(uid).get();
  const data = userSnap.data() ?? {};
  return {
    uid,
    displayName: String(data.displayName ?? authDisplayName ?? "Reader"),
    avatarColor: String(data.avatarColor ?? "blue"),
    readScore: Number(data.readScore ?? STARTING_READ_SCORE),
    currentStreak: Number(data.currentStreak ?? 0),
    officialQuestionsAnswered: Number(data.officialQuestionsAnswered ?? 0),
  };
}

async function fanOutFriendProfile(row: LeaderboardInput): Promise<number> {
  const friendsSnap = await db
    .collectionGroup("friends")
    .where("uid", "==", row.uid)
    .get();
  const writes = friendsSnap.docs
    .filter((doc) => doc.data().status !== "removed")
    .map((doc) => (batch: WriteBatch) => batch.set(doc.ref, {
      displayName: row.displayName ?? "Reader",
      avatarColor: row.avatarColor ?? "blue",
      readScore: row.readScore,
      currentStreak: row.currentStreak ?? 0,
      officialQuestionsAnswered: row.officialQuestionsAnswered,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  await commitBatchedWrites(writes);
  return writes.length;
}

async function disableInvalidNotificationTokens(
  batch: WriteBatch,
  tokens: NotificationToken[],
  responseCodes: string[],
): Promise<number> {
  let disabled = 0;
  responseCodes.forEach((code, index) => {
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      batch.set(db.doc(tokens[index].refPath), {
        enabled: false,
        disabledReason: code,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      disabled += 1;
    }
  });
  return disabled;
}

async function sendNotificationToTokens(
  tokens: NotificationToken[],
  payload: NotificationPayload,
): Promise<{
  attempted: number;
  successCount: number;
  failureCount: number;
  disabledCount: number;
}> {
  let successCount = 0;
  let failureCount = 0;
  let disabledCount = 0;

  for (const chunk of chunkArray(tokens, MAX_FCM_TOKENS_PER_SEND)) {
    const response = await getMessaging().sendEachForMulticast({
      tokens: chunk.map((item) => item.token),
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: {
        route: payload.route,
        type: payload.type,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
      webpush: {
        fcmOptions: {
          link: `${APP_URL}${payload.route}`,
        },
      },
    });
    successCount += response.successCount;
    failureCount += response.failureCount;
    const failedCodes = response.responses.map((item) => item.error?.code ?? "");
    const batch = db.batch();
    disabledCount += await disableInvalidNotificationTokens(batch, chunk, failedCodes);
    await batch.commit();
  }

  return {
    attempted: tokens.length,
    successCount,
    failureCount,
    disabledCount,
  };
}

async function enabledNotificationTokensForUser(uid: string): Promise<NotificationToken[]> {
  const tokensSnap = await db.collection("users").doc(uid)
    .collection("notificationTokens")
    .where("enabled", "==", true)
    .get();
  return tokensSnap.docs
    .map((doc) => ({
      uid,
      refPath: doc.ref.path,
      token: String(doc.data().token ?? ""),
    }))
    .filter((token) => token.token.length > 0);
}

async function sendDailyHabitEmailsToUsersWithoutPush(dailyKey: string): Promise<{
  attempted: number;
  sent: number;
  skippedWithPush: number;
  skippedUnverified: number;
  failed: number;
}> {
  let attempted = 0;
  let sent = 0;
  let skippedWithPush = 0;
  let skippedUnverified = 0;
  let failed = 0;

  let lastDoc: QueryDocumentSnapshot | null = null;
  while (true) {
    let query: Query<DocumentData> = db.collection("users")
      .where("dailyReminder", "==", true)
      .orderBy(FieldPath.documentId())
      .limit(1000);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const usersSnap = await query.get();
    if (usersSnap.empty) break;
    lastDoc = usersSnap.docs[usersSnap.docs.length - 1];

    for (const userDoc of usersSnap.docs) {
      const data = userDoc.data();
      if (data.lastDailyHabitEmailKey === dailyKey) continue;
      const tokens = await enabledNotificationTokensForUser(userDoc.id);
      if (tokens.length > 0) {
        skippedWithPush += 1;
        continue;
      }
      attempted += 1;
      const authUser = await getAuth().getUser(userDoc.id).catch(() => null);
      const email = String(authUser?.email ?? "").trim().toLowerCase();
      if (!authUser?.emailVerified || !isValidEmail(email)) {
        skippedUnverified += 1;
        continue;
      }
      try {
        await sendPostmarkEmail(dailyHabitEmail({
          to: email,
          displayName: String(data.displayName ?? authUser.displayName ?? "Reader"),
          roomsUrl: `${APP_URL}/rooms`,
          dailyKey,
        }));
        await userDoc.ref.set({
          lastDailyHabitEmailKey: dailyKey,
          lastDailyHabitEmailSentAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        sent += 1;
      } catch (error) {
        failed += 1;
        logger.warn("Daily habit email failed", { uid: userDoc.id, error: String(error) });
      }
    }
  }

  return { attempted, sent, skippedWithPush, skippedUnverified, failed };
}

/**
 * A link shared to a big crowd (e.g. an office of 150) shouldn't storm every
 * existing member with a push each. Above this fan-out we skip the per-join
 * notification entirely [Mike: most rooms are <=20, joins are slow].
 */
const MAX_JOIN_NOTIFY_FANOUT = 30;

/** Cap the World leaderboard's peer set (union of your rooms' members). */
const WORLD_LEADERBOARD_PEER_CAP = 500;

/**
 * Notify every existing room member that someone new joined. Members who have
 * already locked answers for the open day get an "update your predictions?"
 * prompt that deep-links into the room's edit flow; everyone else gets a plain
 * heads-up. No em dashes in notification copy [Mike].
 */
async function notifyMembersOfJoin(input: {
  roomId: string;
  creatorUid: string;
  joinedUid: string;
  joinedName: string;
  roomName: string;
}): Promise<void> {
  const membersSnap = await roomRef(input.roomId).collection("members").get();
  const recipientUids = membersSnap.docs
    .map((doc) => doc.id)
    .filter((id) => id !== input.joinedUid);
  if (recipientUids.length === 0 || recipientUids.length > MAX_JOIN_NOTIFY_FANOUT) {
    return;
  }

  // Members with a locked answer for the open day can revise predictions now.
  const roomSnap = await roomRef(input.roomId).get();
  const currentDailyKey = String(roomSnap.data()?.currentDailyKey ?? "");
  let answeredUids = new Set<string>();
  if (currentDailyKey) {
    const answersSnap = await roomDayRef(input.roomId, currentDailyKey)
      .collection("answers")
      .get();
    answeredUids = new Set(answersSnap.docs.map((doc) => doc.id));
  }

  for (const uid of recipientUids) {
    const userSnap = await db.collection("users").doc(uid).get();
    const profile = userSnap.data() ?? {};
    if (profile.dailyReminder === false) continue;

    const canUpdate = answeredUids.has(uid);
    const payload = {
      title: input.roomName,
      body: canUpdate
        ? `${input.joinedName} joined. Want to update your predictions?`
        : `${input.joinedName} joined ${input.roomName}.`,
      route: canUpdate
        ? `/rooms/${input.roomId}?edit=1`
        : `/rooms/${input.roomId}`,
      type: "room_member_joined" as const,
    };

    const tokens = await enabledNotificationTokensForUser(uid);
    if (tokens.length > 0) {
      await sendNotificationToTokens(tokens, payload);
      continue;
    }

    // Email fallback keeps the prior creator-only behavior for push-less users.
    if (uid !== input.creatorUid) continue;
    const authUser = await getAuth().getUser(uid).catch(() => null);
    const email = String(authUser?.email ?? "").trim().toLowerCase();
    if (!authUser?.emailVerified || !isValidEmail(email)) continue;
    await sendPostmarkEmail(memberJoinedEmail({
      to: email,
      displayName: String(profile.displayName ?? authUser.displayName ?? "Reader"),
      joinedName: input.joinedName,
      roomName: input.roomName,
      roomUrl: `${APP_URL}/rooms/${input.roomId}`,
    }));
  }
}

async function aggregateQuestionCounters(questionId: string): Promise<Record<string, number>> {
  const shards = await db.collection("questionCounters").doc(questionId).collection("shards").get();
  const distribution: Record<string, number> = { total: 0 };
  for (const shard of shards.docs) {
    const data = shard.data();
    distribution.total += Number(data.total ?? 0);
    const options = (data.options ?? {}) as Record<string, number>;
    for (const [optionId, count] of Object.entries(options)) {
      distribution[optionId] = (distribution[optionId] ?? 0) + Number(count ?? 0);
    }
  }
  return distribution;
}

function adminQuestionSummary(
  id: string,
  data: DocumentData,
): AdminQuestionSummary {
  return {
    id,
    prompt: String(data.prompt ?? ""),
    category: String(data.category ?? ""),
    status: String(data.status ?? "draft"),
    dailyKey: String(data.dailyKey ?? ""),
    publishAt: timestampIso(data.publishAt),
    closeAt: timestampIso(data.closeAt),
    options: Array.isArray(data.options)
      ? data.options.map((option) => ({
        id: String(option?.id ?? ""),
        label: String(option?.label ?? ""),
      })).filter((option) => option.id.length > 0 && option.label.length > 0)
      : [],
  };
}

function sortAdminQuestions(questions: AdminQuestionSummary[]): AdminQuestionSummary[] {
  return [...questions].sort((a, b) => {
    const aKey = a.dailyKey || "0000-00-00";
    const bKey = b.dailyKey || "0000-00-00";
    if (aKey !== bKey) return bKey.localeCompare(aKey);
    return a.prompt.localeCompare(b.prompt);
  });
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return Math.round(((sorted[middle - 1] + sorted[middle]) / 2) * 10) / 10;
}

function pct(part: number, total: number): number {
  return total <= 0 ? 0 : Math.round((part / total) * 100);
}

async function countQuery(query: Query): Promise<number> {
  const snapshot = await query.count().get();
  return snapshot.data().count;
}

async function adminAnswerStats(questionId: string): Promise<{
  avgPredictedShare: number | null;
  medianReadAccuracy: number | null;
  highAccuracyPct: number | null;
  accuracyBuckets: Record<string, number>;
}> {
  const answers = await db
    .collectionGroup("answers")
    .where("questionId", "==", questionId)
    .where("official", "==", true)
    .limit(1000)
    .get();

  const predictedShares: number[] = [];
  const accuracies: number[] = [];
  const bucketCounts: Record<string, number> = {
    "0-20": 0,
    "21-40": 0,
    "41-60": 0,
    "61-80": 0,
    "81-100": 0,
  };

  for (const doc of answers.docs) {
    const data = doc.data();
    const predictedShare = Number(data.predictedShare);
    if (Number.isFinite(predictedShare)) predictedShares.push(predictedShare);
    const readAccuracy = Number(data.readAccuracy);
    if (Number.isFinite(readAccuracy)) {
      accuracies.push(readAccuracy);
      if (readAccuracy <= 20) bucketCounts["0-20"] += 1;
      else if (readAccuracy <= 40) bucketCounts["21-40"] += 1;
      else if (readAccuracy <= 60) bucketCounts["41-60"] += 1;
      else if (readAccuracy <= 80) bucketCounts["61-80"] += 1;
      else bucketCounts["81-100"] += 1;
    }
  }

  const accuracyTotal = accuracies.length;
  return {
    avgPredictedShare: predictedShares.length === 0
      ? null
      : Math.round(predictedShares.reduce((sum, value) => sum + value, 0) / predictedShares.length),
    medianReadAccuracy: median(accuracies),
    highAccuracyPct: pct(accuracies.filter((value) => value >= 90).length, accuracyTotal),
    accuracyBuckets: Object.fromEntries(
      Object.entries(bucketCounts).map(([key, value]) => [key, pct(value, accuracyTotal)]),
    ),
  };
}

async function adminResultSummary(
  questionId: string,
  data: DocumentData,
  questionStatus: string,
  includeAnswerStats: boolean,
): Promise<AdminResultSummary> {
  const answerStats = includeAnswerStats
    ? await adminAnswerStats(questionId)
    : {
      avgPredictedShare: null,
      medianReadAccuracy: null,
      highAccuracyPct: null,
      accuracyBuckets: {},
    };

  return {
    questionId,
    prompt: String(data.prompt ?? ""),
    category: String(data.category ?? ""),
    dailyKey: String(data.dailyKey ?? ""),
    status: questionStatus,
    options: Array.isArray(data.options)
      ? data.options.map((option) => ({
        id: String(option?.id ?? ""),
        label: String(option?.label ?? ""),
      })).filter((option) => option.id.length > 0 && option.label.length > 0)
      : [],
    totalAnswers: Number(data.totalAnswers ?? 0),
    optionCounts: numericRecord(data.optionCounts),
    optionPcts: numericRecord(data.optionPcts),
    countedTowardScore: data.countedTowardScore === true,
    closedAt: timestampIso(data.closedAt),
    ...answerStats,
  };
}

function ageBucketForBirthdate(value: unknown): string {
  if (typeof value !== "string") return "Unknown";
  const birthdate = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(birthdate.getTime())) return "Unknown";
  const now = new Date();
  let age = now.getUTCFullYear() - birthdate.getUTCFullYear();
  const birthdayPassed =
    now.getUTCMonth() > birthdate.getUTCMonth() ||
    (now.getUTCMonth() === birthdate.getUTCMonth() && now.getUTCDate() >= birthdate.getUTCDate());
  if (!birthdayPassed) age -= 1;
  if (age < 18) return "Under 18";
  if (age <= 24) return "18-24";
  if (age <= 34) return "25-34";
  if (age <= 44) return "35-44";
  if (age <= 54) return "45-54";
  return "55+";
}

function incrementMap(map: Record<string, number>, key: string): void {
  map[key] = (map[key] ?? 0) + 1;
}

function bucketRows(
  buckets: Record<string, number>,
  total: number,
): Array<{ label: string; value: number; count: number }> {
  return Object.entries(buckets)
    .filter(([label]) => label.length > 0)
    .sort((a, b) => b[1] - a[1])
    .map(([label, count]) => ({
      label,
      value: pct(count, total),
      count,
    }));
}

async function adminDailyCompletionRows(): Promise<Array<{
  label: string;
  completers: number;
  returningCompleters: number;
  newCompleters: number;
  returningPct: number;
}>> {
  const todayKey = dailyKeyForEasternDate(new Date());
  const outputDayCount = 30;
  const lookbackDayCount = 120;
  const firstOutputKey = addDaysToDailyKey(todayKey, -(outputDayCount - 1));
  const firstLookbackKey = addDaysToDailyKey(todayKey, -(lookbackDayCount - 1));
  const outputKeys = Array.from({ length: outputDayCount }, (_, index) =>
    addDaysToDailyKey(firstOutputKey, index));
  const usersByDay = new Map<string, Set<string>>();

  const roomsSnap = await db.collection("rooms").limit(500).get();
  await Promise.all(roomsSnap.docs.map(async (roomDoc) => {
    const daysSnap = await roomDoc.ref
      .collection("days")
      .where(FieldPath.documentId(), ">=", firstLookbackKey)
      .where(FieldPath.documentId(), "<=", todayKey)
      .get();

    await Promise.all(daysSnap.docs.map(async (dayDoc) => {
      const answersSnap = await dayDoc.ref.collection("answers").get();
      if (answersSnap.empty) return;
      let users = usersByDay.get(dayDoc.id);
      if (!users) {
        users = new Set<string>();
        usersByDay.set(dayDoc.id, users);
      }
      for (const answerDoc of answersSnap.docs) {
        users.add(answerDoc.id);
      }
    }));
  }));

  const firstCompletionDayByUid = new Map<string, string>();
  for (const dailyKey of [...usersByDay.keys()].sort()) {
    const users = usersByDay.get(dailyKey) ?? new Set<string>();
    for (const uid of users) {
      if (!firstCompletionDayByUid.has(uid)) {
        firstCompletionDayByUid.set(uid, dailyKey);
      }
    }
  }

  return outputKeys.map((dailyKey) => {
    const users = usersByDay.get(dailyKey) ?? new Set<string>();
    const returningCompleters = [...users].filter((uid) => {
      const firstCompletionDay = firstCompletionDayByUid.get(uid);
      return Boolean(firstCompletionDay && firstCompletionDay < dailyKey);
    }).length;
    const completers = users.size;
    return {
      label: dailyKey,
      completers,
      returningCompleters,
      newCompleters: Math.max(0, completers - returningCompleters),
      returningPct: pct(returningCompleters, completers),
    };
  });
}

function optionPercentages(question: Question, counts: Record<string, number>): Record<string, number> {
  const total = counts.total || 0;
  const percentages: Record<string, number> = {};
  for (const option of question.options) {
    percentages[option.id] = total === 0 ? 0 : Math.round(((counts[option.id] ?? 0) / total) * 100);
  }
  return percentages;
}

function assertPracticeSource(value: unknown): string {
  const source = assertString(value ?? "history-replay", "source");
  if (!isPracticeAnswerSource(source)) {
    throw new HttpsError("invalid-argument", "source is not valid for a practice answer.");
  }
  return source;
}

async function officialAnswersForQuestion(questionId: string): Promise<OfficialAnswer[]> {
  const snapshot = await db
    .collectionGroup("answers")
    .where("questionId", "==", questionId)
    .where("official", "==", true)
    .get();

  return snapshot.docs.map((doc) => ({
    uid: doc.ref.parent.parent?.id ?? "",
    refPath: doc.ref.path,
    questionId,
    selectedOptionId: String(doc.data().selectedOptionId),
    predictedShare: Number(doc.data().predictedShare),
    source: String(doc.data().source ?? "daily"),
  })).filter((answer) => answer.uid.length > 0);
}

async function applyScoredAnswer(
  answer: OfficialAnswer,
  question: Question,
  optionPcts: Record<string, number>,
  readAccuracy: number,
  dailyPercentile: number,
  countedTowardScore: boolean,
): Promise<void> {
  const answerRef = db.doc(answer.refPath);
  const userRef = db.collection("users").doc(answer.uid);
  const categoryRef = userRef.collection("categoryStats").doc(question.category);
  const historyRef = userRef.collection("scoreHistory").doc(answer.questionId);
  const actualShare = optionPcts[answer.selectedOptionId] ?? 0;
  const predictionBias = calculatePredictionBias(answer.predictedShare, actualShare);
  const predictionError = Math.abs(predictionBias);

  await db.runTransaction(async (tx) => {
    const answerSnap = await tx.get(answerRef);
    const userSnap = await tx.get(userRef);
    const categorySnap = await tx.get(categoryRef);
    const previousAnswer = answerSnap.exists ? answerSnap.data() ?? {} : {};
    const user = userSnap.exists ? userSnap.data() ?? {} : {};
    const priorScoreApplied =
      previousAnswer.countedTowardScore === true &&
      (previousAnswer.scoreApplied === true || previousAnswer.scored === true);
    const priorStreakApplied =
      previousAnswer.streakApplied === true || previousAnswer.scored === true;
    const priorDelta = priorScoreApplied
      ? Number(previousAnswer.readScoreDelta ?? 0)
      : 0;
    const priorAccuracy = priorScoreApplied
      ? Number(previousAnswer.readAccuracy ?? 0)
      : 0;
    const priorBias = priorScoreApplied
      ? Number(previousAnswer.predictionBias ?? 0)
      : 0;
    const officialQuestionsAnswered = Math.max(
      0,
      Number(user.officialQuestionsAnswered ?? 0) - (priorScoreApplied ? 1 : 0),
    );
    const delta = countedTowardScore
      ? scoreDeltaForPercentile(dailyPercentile, officialQuestionsAnswered)
      : 0;
    const previousScore = Number(user.readScore ?? STARTING_READ_SCORE);
    const nextScore = previousScore - priorDelta + delta;
    const previousDailyKey = String(user.lastAnsweredDailyKey ?? "");
    const currentStreak = Number(user.currentStreak ?? 0);
    const shouldApplyStreak = !priorStreakApplied && question.dailyKey != null;
    const nextStreak = shouldApplyStreak
      ? nextStreakForDailyKey(previousDailyKey || null, String(question.dailyKey), currentStreak)
      : currentStreak;
    const userUpdate: Record<string, unknown> = {
      readScore: nextScore,
      officialQuestionsAnswered: officialQuestionsAnswered + (countedTowardScore ? 1 : 0),
      lastScoredQuestionId: answer.questionId,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const nextBiasCount = officialQuestionsAnswered + (countedTowardScore ? 1 : 0);
    const nextBiasSum =
      Number(user.predictionBiasSum ?? 0) - priorBias +
      (countedTowardScore ? predictionBias : 0);
    if (countedTowardScore || priorScoreApplied) {
      const averagePredictionBias =
        nextBiasCount > 0 ? Math.round((nextBiasSum / nextBiasCount) * 10) / 10 : 0;
      userUpdate.predictionBiasSum = nextBiasSum;
      userUpdate.averagePredictionBias = averagePredictionBias;
      userUpdate.predictionBiasDirection = averagePredictionBiasLabel(averagePredictionBias);
    }
    if (shouldApplyStreak) {
      userUpdate.currentStreak = nextStreak;
      userUpdate.longestStreak = Math.max(Number(user.longestStreak ?? 0), nextStreak);
      userUpdate.lastAnsweredDailyKey = question.dailyKey ?? null;
    }

    tx.set(answerRef, {
      actualShare,
      readAccuracy,
      predictionError,
      predictionBias,
      dailyPercentile,
      readScoreDelta: delta,
      countedTowardScore,
      scoreApplied: countedTowardScore,
      streakApplied: priorStreakApplied || shouldApplyStreak,
      scored: true,
      scoredAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(userRef, userUpdate, { merge: true });

    const cat = categorySnap.exists ? categorySnap.data() ?? {} : {};
    const nextCount =
      Math.max(0, Number(cat.count ?? 0) - (priorScoreApplied ? 1 : 0)) +
      (countedTowardScore ? 1 : 0);
    const nextAccuracySum =
      Math.max(0, Number(cat.accuracySum ?? 0) - priorAccuracy) +
      (countedTowardScore ? readAccuracy : 0);
    const nextBiasSumForCategory =
      Number(cat.biasSum ?? 0) - priorBias +
      (countedTowardScore ? predictionBias : 0);
    const averageCategoryBias =
      nextCount > 0 ? Math.round((nextBiasSumForCategory / nextCount) * 10) / 10 : 0;
    tx.set(categoryRef, {
      category: question.category,
      count: nextCount,
      accuracySum: nextAccuracySum,
      averageReadAccuracy: nextCount > 0 ? Math.round((nextAccuracySum / nextCount) * 10) / 10 : 0,
      smoothedCategoryScore: nextCount > 0 ? smoothedCategoryScore(nextAccuracySum, nextCount) : 0,
      biasSum: nextBiasSumForCategory,
      averagePredictionBias: averageCategoryBias,
      predictionBiasDirection: averagePredictionBiasLabel(averageCategoryBias),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(historyRef, {
      questionId: answer.questionId,
      category: question.category,
      readAccuracy,
      predictionError,
      predictionBias,
      dailyPercentile,
      readScoreDelta: delta,
      countedTowardScore,
      scoreApplied: countedTowardScore,
      streakApplied: priorStreakApplied || shouldApplyStreak,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function closeQuestion(questionId: string, force = false): Promise<{
  questionId: string;
  totalAnswers: number;
  scoredAnswers: number;
}> {
  const questionRef = db.collection("questions").doc(questionId);
  const questionSnap = await questionRef.get();
  if (!questionSnap.exists) {
    throw new HttpsError("not-found", `Question ${questionId} does not exist.`);
  }

  const question = questionSnap.data() as Question;
  const now = Timestamp.now();
  const closeAtMillis = timestampMillis(question.closeAt);
  if (!force && (question.status !== "live" || (closeAtMillis != null && closeAtMillis > now.toMillis()))) {
    return { questionId, totalAnswers: 0, scoredAnswers: 0 };
  }

  const counts = await aggregateQuestionCounters(questionId);
  const optionPcts = optionPercentages(question, counts);
  const totalAnswers = counts.total ?? 0;
  const answers = await officialAnswersForQuestion(questionId);
  const minimumScoredResponses = Number(process.env.MINIMUM_SCORED_RESPONSES ?? 50);
  const countedTowardScore = totalAnswers >= minimumScoredResponses;

  const scored = answers.map((answer) => {
    const actualShare = optionPcts[answer.selectedOptionId] ?? 0;
    return {
      answer,
      readAccuracy: calculateReadAccuracy(answer.predictedShare, actualShare),
    };
  });
  const percentiles = dailyPercentilesByAccuracy(scored.map((item) => item.readAccuracy));

  const resultRef = db.collection("dailyResults").doc(questionId);
  const resultSnap = await resultRef.get();
  const resultUpdate: Record<string, unknown> = {
    questionId,
    dailyKey: question.dailyKey ?? null,
    category: question.category,
    prompt: question.prompt,
    status: "closed",
    options: question.options,
    optionCounts: Object.fromEntries(question.options.map((option) => [option.id, counts[option.id] ?? 0])),
    optionPcts,
    totalAnswers,
    countedTowardScore,
  };
  if (!resultSnap.exists || resultSnap.data()?.closedAt == null) {
    resultUpdate.closedAt = FieldValue.serverTimestamp();
  }
  await resultRef.set(resultUpdate, { merge: true });

  for (const item of scored) {
    await applyScoredAnswer(
      item.answer,
      question,
      optionPcts,
      item.readAccuracy,
      percentiles.get(item.readAccuracy) ?? 0,
      countedTowardScore,
    );
  }

  const questionUpdate: Record<string, unknown> = {
    status: "closed",
    totalAnswers,
  };
  if (questionSnap.data()?.closedAt == null) {
    questionUpdate.closedAt = FieldValue.serverTimestamp();
  }
  await questionRef.set(questionUpdate, { merge: true });

  if (scored.length > 0) {
    await recomputeGlobalLeaderboard();
  }

  return { questionId, totalAnswers, scoredAnswers: scored.length };
}

export const submitPrediction = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const questionId = assertString(request.data?.questionId, "questionId");
  const selectedOptionId = assertString(request.data?.selectedOptionId, "selectedOptionId");
  const predictedShare = assertPrediction(request.data?.predictedShare);

  const result = await db.runTransaction(async (tx) => {
    const questionRef = db.collection("questions").doc(questionId);
    const questionSnap = await tx.get(questionRef);
    if (!questionSnap.exists) {
      throw new HttpsError("not-found", "Question not found.");
    }

    const question = questionSnap.data() as Question;
    if (question.status !== "live") {
      throw new HttpsError("failed-precondition", "This question is not live.");
    }
    if (!question.options.some((option) => option.id === selectedOptionId)) {
      throw new HttpsError("invalid-argument", "Selected option is not valid for this question.");
    }

    const nowMs = Date.now();
    const publishAtMs = timestampMillis(question.publishAt);
    const closeAtMs = timestampMillis(question.closeAt);
    if ((publishAtMs != null && nowMs < publishAtMs) || (closeAtMs != null && nowMs >= closeAtMs)) {
      throw new HttpsError("failed-precondition", "This question is outside its official window.");
    }

    const userRef = db.collection("users").doc(uid);
    const answerRef = userRef.collection("answers").doc(questionId);
    const userSnap = await tx.get(userRef);
    const existingAnswer = await tx.get(answerRef);
    if (existingAnswer.exists) {
      throw new HttpsError("already-exists", "This question is already locked.");
    }

    const counterShard = shardId();
    const counterSummaryRef = db.collection("questionCounters").doc(questionId);
    const counterRef = counterSummaryRef.collection("shards").doc(counterShard);

    tx.set(userRef, {
      ...missingUserProgressDefaults(userSnap.data()),
      ...(userSnap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.create(answerRef, {
      questionId,
      selectedOptionId,
      selectedOptionLabel: optionLabels(question)[selectedOptionId],
      predictedShare,
      official: true,
      source: "daily",
      scored: false,
      countedTowardScore: false,
      counterShard,
      counterRefPath: counterRef.path,
      lockedAt: FieldValue.serverTimestamp(),
    });

    tx.set(counterRef, {
      total: FieldValue.increment(1),
      options: {
        [selectedOptionId]: FieldValue.increment(1),
      },
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(counterSummaryRef, {
      questionId,
      total: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
      locked: true,
      questionId,
      selectedOptionId,
      predictedShare,
    };
  });

  return result;
});

export const createAuthHandoff = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const targetRoute = assertAppRoute(request.data?.targetRoute, "/today");
  const rawQuestionId = typeof request.data?.questionId === "string"
    ? request.data.questionId.trim()
    : "";
  const rawSelectedOptionId = typeof request.data?.selectedOptionId === "string"
    ? request.data.selectedOptionId.trim()
    : "";
  const rawPredictedShare = request.data?.predictedShare;

  let questionId: string | null = null;
  let selectedOptionId: string | null = null;
  let predictedShare: number | null = null;

  if (rawQuestionId || rawSelectedOptionId || rawPredictedShare != null) {
    questionId = assertString(rawQuestionId, "questionId");
    selectedOptionId = assertString(rawSelectedOptionId, "selectedOptionId");
    predictedShare = assertPrediction(rawPredictedShare);
    const questionSnap = await db.collection("questions").doc(questionId).get();
    if (!questionSnap.exists) {
      throw new HttpsError("not-found", "Question not found.");
    }
    const question = questionSnap.data() as Question;
    if (question.status !== "live") {
      throw new HttpsError("failed-precondition", "This question is not live.");
    }
    if (!question.options.some((option) => option.id === selectedOptionId)) {
      throw new HttpsError("invalid-argument", "Selected option is not valid for this question.");
    }
  }

  const [authUser, userSnap] = await Promise.all([
    getAuth().getUser(uid),
    db.collection("users").doc(uid).get(),
  ]);
  const userData = userSnap.data();
  await db.collection("users").doc(uid).set({
    ...missingUserProgressDefaults(userData),
    ...(!userSnap.exists ? { createdAt: FieldValue.serverTimestamp() } : {}),
    ...(!userSnap.exists || typeof userData?.email !== "string"
      ? { email: authUser.email ?? null }
      : {}),
    ...(!userSnap.exists || typeof userData?.displayName !== "string"
      ? { displayName: authUser.displayName ?? authUser.email?.split("@")[0] ?? "Reader" }
      : {}),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const code = await createAuthHandoffDocument({
    uid,
    questionId,
    selectedOptionId,
    predictedShare,
    targetRoute,
  });
  return {
    code,
    appUrl: `${APP_URL}/auth?handoff=${encodeURIComponent(code)}`,
    expiresInSeconds: Math.floor(AUTH_HANDOFF_TTL_MS / 1000),
  };
});

export const redeemAuthHandoff = onCall(callableOptions, async (request) => {
  const code = assertString(request.data?.code, "code").toUpperCase();
  let payload: AuthHandoffPayload | null = null;

  await db.runTransaction(async (tx) => {
    const ref = db.collection("authHandoffs").doc(code);
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    if (!snap.exists || !["active", "redeemed"].includes(String(data.status ?? ""))) {
      throw new HttpsError("not-found", "Auth handoff not found.");
    }
    const expiresAt = timestampDate(data.expiresAt);
    if (expiresAt == null || expiresAt.getTime() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "Auth handoff has expired.");
    }
    const uid = String(data.uid ?? "");
    if (!uid) {
      throw new HttpsError("failed-precondition", "Auth handoff is invalid.");
    }
    payload = {
      uid,
      questionId: typeof data.questionId === "string" ? data.questionId : null,
      selectedOptionId: typeof data.selectedOptionId === "string" ? data.selectedOptionId : null,
      predictedShare: typeof data.predictedShare === "number" ? data.predictedShare : null,
      targetRoute: typeof data.targetRoute === "string" ? data.targetRoute : "/today",
    };
    if (data.status === "active") {
      tx.set(ref, {
        status: "redeemed",
        redeemedAt: FieldValue.serverTimestamp(),
        lastRedeemedAt: FieldValue.serverTimestamp(),
        redeemAttempts: FieldValue.increment(1),
      }, { merge: true });
    }
  });

  if (payload == null) {
    throw new HttpsError("not-found", "Auth handoff not found.");
  }
  const redeemedPayload = payload as AuthHandoffPayload;
  const userSnap = await db.collection("users").doc(redeemedPayload.uid).get();
  const customToken = await getAuth().createCustomToken(redeemedPayload.uid, {
    source: "landing_handoff",
  });
  return {
    customToken,
    questionId: redeemedPayload.questionId,
    selectedOptionId: redeemedPayload.selectedOptionId,
    predictedShare: redeemedPayload.predictedShare,
    targetRoute: redeemedPayload.targetRoute,
    hasCompletedDemographics: hasCompletedDemographics(userSnap.data()),
  };
});

export const savePracticeAnswer = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const questionId = assertString(request.data?.questionId, "questionId");
  const selectedOptionId = assertString(request.data?.selectedOptionId, "selectedOptionId");
  const predictedShare = assertPrediction(request.data?.predictedShare);
  const source = assertPracticeSource(request.data?.source);
  const result = await requireRevealedResult(
    questionId,
    "Only closed questions can be saved as practice answers.",
  );
  const options = Array.isArray(result.options) ? result.options as QuestionOption[] : [];
  if (!options.some((option) => option.id === selectedOptionId)) {
    throw new HttpsError("invalid-argument", "Selected option is not valid for this question.");
  }

  const optionPcts = (result.optionPcts ?? {}) as Record<string, number>;
  const actualShare = Number(optionPcts[selectedOptionId] ?? 0);
  const readAccuracy = calculateReadAccuracy(predictedShare, actualShare);
  const predictionBias = calculatePredictionBias(predictedShare, actualShare);
  const predictionError = Math.abs(predictionBias);
  const userRef = db.collection("users").doc(uid);
  const answerRef = userRef.collection("answers").doc(questionId);

  const saved = await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const answerSnap = await tx.get(answerRef);
    if (answerSnap.exists && answerSnap.data()?.official === true) {
      return false;
    }

    if (userSnap.exists) {
      tx.set(userRef, {
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      tx.set(userRef, {
        readScore: STARTING_READ_SCORE,
        officialQuestionsAnswered: 0,
        currentStreak: 0,
        longestStreak: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    tx.set(answerRef, {
      questionId,
      selectedOptionId,
      selectedOptionLabel: optionLabels({
        category: String(result.category ?? ""),
        prompt: String(result.prompt ?? ""),
        options,
        status: "closed",
      })[selectedOptionId],
      predictedShare,
      actualShare,
      readAccuracy,
      predictionError,
      predictionBias,
      official: false,
      source,
      scored: true,
      countedTowardScore: false,
      scoreApplied: false,
      lockedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  });

  return { saved, officialPreserved: !saved, questionId, readAccuracy, predictionBias };
});

async function clearUserData(uid: string) {
  const userRef = db.collection("users").doc(uid);
  const answersSnap = await userRef.collection("answers").get();
  const friendsSnap = await userRef.collection("friends").get();

  const cleanupWrites: Array<(batch: WriteBatch) => void> = [];
  for (const answer of answersSnap.docs) {
    const data = answer.data();
    const counterRefPath = String(data.counterRefPath ?? "");
    const selectedOptionId = String(data.selectedOptionId ?? "");
    const shouldDecrementLiveCounter =
      data.official === true &&
      data.scored !== true &&
      counterRefPath.length > 0 &&
      selectedOptionId.length > 0;
    if (shouldDecrementLiveCounter) {
      cleanupWrites.push((batch) => batch.set(db.doc(counterRefPath), {
        total: FieldValue.increment(-1),
        options: {
          [selectedOptionId]: FieldValue.increment(-1),
        },
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true }));
    }
  }

  for (const friend of friendsSnap.docs) {
    cleanupWrites.push((batch) => batch.delete(
      db.collection("users").doc(friend.id).collection("friends").doc(uid),
    ));
  }

  cleanupWrites.push((batch) => batch.delete(
    db.collection("leaderboards").doc("global").collection("rows").doc(uid),
  ));
  cleanupWrites.push((batch) => batch.set(userRef, {
    readScore: STARTING_READ_SCORE,
    officialQuestionsAnswered: 0,
    currentStreak: 0,
    longestStreak: 0,
    predictionBiasSum: FieldValue.delete(),
    averagePredictionBias: FieldValue.delete(),
    predictionBiasDirection: FieldValue.delete(),
    readScorePercentile: FieldValue.delete(),
    lastScoredQuestionId: FieldValue.delete(),
    lastAnsweredDailyKey: FieldValue.delete(),
    dailyReminder: false,
    leaderboardRank: FieldValue.delete(),
    leaderboardUpdatedAt: FieldValue.delete(),
    clearedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true }));
  await commitBatchedWrites(cleanupWrites);
  const shareData = await clearServerOwnedShareData(uid);

  const deleted = {
    answers: await deleteUserSubcollection(uid, "answers"),
    answerDrafts: await deleteUserSubcollection(uid, "answerDrafts"),
    scoreHistory: await deleteUserSubcollection(uid, "scoreHistory"),
    categoryStats: await deleteUserSubcollection(uid, "categoryStats"),
    friends: await deleteUserSubcollection(uid, "friends"),
    notificationTokens: await deleteUserSubcollection(uid, "notificationTokens"),
    links: shareData.links,
    invitesCreated: shareData.invitesCreated,
    invitesAcceptedUpdated: shareData.invitesAcceptedUpdated,
  };
  await recomputeGlobalLeaderboard();
  return { cleared: true, deleted };
}

export const clearMyData = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  return clearUserData(uid);
});

export const deleteMyAccount = onCall(accountDeletionCallableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const userRef = db.collection("users").doc(uid);
  const [userSnap, membershipsSnap] = await Promise.all([
    userRef.get(),
    userRef.collection("memberships").get(),
  ]);
  const profile = userSnap.data() ?? {};
  const roomIds = membershipsSnap.docs
    .map((doc) => String(doc.data().roomId ?? doc.id))
    .filter((roomId) => roomId.length > 0);

  for (const roomId of roomIds) {
    await applyUserDislikesToRoom(uid, roomId, -1);
    await removeAccountFromRoom(uid, roomId);
  }

  const reactionWrites: Array<(batch: WriteBatch) => void> = [];
  const likedQuestionIds = Array.isArray(profile.likedQuestionIds)
    ? profile.likedQuestionIds.map(String)
    : [];
  const dislikedQuestionIds = Array.isArray(profile.dislikedQuestionIds)
    ? profile.dislikedQuestionIds.map(String)
    : [];
  for (const qid of likedQuestionIds) {
    reactionWrites.push((batch) => batch.set(db.collection("questionFeedback").doc(qid), {
      likedCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }
  for (const qid of dislikedQuestionIds) {
    reactionWrites.push((batch) => batch.set(db.collection("questionFeedback").doc(qid), {
      dislikedCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }
  await commitBatchedWrites(reactionWrites);

  await clearUserData(uid);
  const personalRefs = uniqueRefs((await Promise.all([
    refsForQuery(db.collection("feedback").where("uid", "==", uid)),
    refsForQuery(db.collection("waitlist").where("uid", "==", uid)),
    refsForQuery(db.collection("flags").where("flaggedBy", "==", uid)),
    refsForQuery(db.collection("flags").where("authorUid", "==", uid)),
    refsForQuery(db.collection("authHandoffs").where("uid", "==", uid)),
  ])).flat());
  await commitBatchedWrites(personalRefs.map((ref) => (batch) => batch.delete(ref)));
  await db.recursiveDelete(userRef);
  await getAuth().deleteUser(uid);
  logger.info("Deleted user account", {
    uid,
    rooms: roomIds.length,
    personalDocuments: personalRefs.length,
  });
  return { deleted: true };
});

export const joinWaitlist = onCall(callableOptions, async (request) => {
  const email = normalizeEmail(request.data?.email);
  const source = assertString(request.data?.source ?? "landing", "source").slice(0, 80);
  const answer = typeof request.data?.answer === "string" ? request.data.answer.slice(0, 80) : null;
  const predictedShare = typeof request.data?.predictedShare === "number"
    ? Math.max(0, Math.min(100, Math.round(request.data.predictedShare)))
    : null;
  const ref = db.collection("waitlist").doc(waitlistDocId(email));

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const base = {
      email,
      source,
      answer,
      predictedShare,
      uid: request.auth?.uid ?? null,
      latestAt: FieldValue.serverTimestamp(),
      signupCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.set(ref, snap.exists ? base : {
      ...base,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return { joined: true };
});

export const listWaitlist = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const requestedLimit = Number(request.data?.limit ?? 100);
  const safeLimit = Math.max(1, Math.min(500, Number.isFinite(requestedLimit) ? requestedLimit : 100));
  const snap = await db
    .collection("waitlist")
    .orderBy("latestAt", "desc")
    .limit(safeLimit)
    .get();

  return {
    rows: snap.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        email: String(data.email ?? ""),
        source: String(data.source ?? ""),
        answer: data.answer == null ? null : String(data.answer),
        predictedShare: typeof data.predictedShare === "number"
          ? data.predictedShare
          : null,
        signupCount: Number(data.signupCount ?? 1),
        uid: data.uid == null ? null : String(data.uid),
        createdAt: timestampIso(data.createdAt),
        latestAt: timestampIso(data.latestAt),
      };
    }),
  };
});

export const getAdminOverview = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const requestedFocusQuestionId = typeof request.data?.questionId === "string"
    ? request.data.questionId.trim()
    : "";
  const sevenDaysAgo = Timestamp.fromDate(new Date(Date.now() - 7 * 24 * 60 * 60 * 1000));

  const [
    questionsSnap,
    resultsSnap,
    totalUsers,
    activeUsers,
    newUsers7d,
    waitlistSignups,
    notificationTokens,
    leaderboardRows,
    activeUserSample,
    completionRows,
  ] = await Promise.all([
    db.collection("questions").limit(120).get(),
    db.collection("dailyResults").orderBy("closedAt", "desc").limit(30).get(),
    countQuery(db.collection("users")),
    countQuery(db.collection("users").where("officialQuestionsAnswered", ">", 0)),
    countQuery(db.collection("users").where("createdAt", ">=", sevenDaysAgo)),
    countQuery(db.collection("waitlist")),
    countQuery(db.collectionGroup("notificationTokens").where("enabled", "==", true)),
    countQuery(db.collection("leaderboards").doc("global").collection("rows")),
    db.collection("users").where("officialQuestionsAnswered", ">", 0).limit(1000).get(),
    adminDailyCompletionRows(),
  ]);

  const questions = sortAdminQuestions(
    questionsSnap.docs.map((doc) => adminQuestionSummary(doc.id, doc.data())),
  );
  const questionStatusById = new Map(questions.map((question) => [question.id, question.status]));
  const liveQuestion = questions.find((question) => question.status === "live") ?? null;
  const focusQuestionId = requestedFocusQuestionId ||
    resultsSnap.docs[0]?.id ||
    liveQuestion?.id ||
    "";

  const results = await Promise.all(resultsSnap.docs.map((doc) => adminResultSummary(
    doc.id,
    doc.data(),
    questionStatusById.get(doc.id) ?? "closed",
    doc.id === focusQuestionId,
  )));

  const liveCounters = liveQuestion
    ? await aggregateQuestionCounters(liveQuestion.id)
    : null;
  const liveOptionCounts = liveQuestion && liveCounters
    ? Object.fromEntries(liveQuestion.options.map((option) => [option.id, liveCounters[option.id] ?? 0]))
    : {};
  const liveOptionPcts = liveQuestion && liveCounters
    ? optionPercentages({
      category: liveQuestion.category,
      prompt: liveQuestion.prompt,
      options: liveQuestion.options,
      status: "live",
      dailyKey: liveQuestion.dailyKey || undefined,
    }, liveCounters)
    : {};

  const categoryAnswerTotals: Record<string, number> = {};
  let resultAnswerTotal = 0;
  for (const result of results) {
    const answerCount = result.totalAnswers;
    resultAnswerTotal += answerCount;
    categoryAnswerTotals[result.category] = (categoryAnswerTotals[result.category] ?? 0) + answerCount;
  }

  const ageBuckets: Record<string, number> = {};
  const genderBuckets: Record<string, number> = {};
  const countryBuckets: Record<string, number> = {};
  let streakSum = 0;
  let activeStreaks = 0;
  const streakThresholds = [
    ["D1", 1],
    ["D3", 3],
    ["D7", 7],
    ["D14", 14],
    ["D30", 30],
  ] as const;
  const streakCounts = Object.fromEntries(streakThresholds.map(([label]) => [label, 0]));

  for (const doc of activeUserSample.docs) {
    const data = doc.data();
    const demographics = data.demographics && typeof data.demographics === "object"
      ? data.demographics as Record<string, unknown>
      : {};
    incrementMap(ageBuckets, ageBucketForBirthdate(demographics.birthdate));
    incrementMap(genderBuckets, String(demographics.gender ?? "Unknown"));
    incrementMap(countryBuckets, String(demographics.country ?? "Unknown"));
    const streak = Number(data.currentStreak ?? 0);
    if (Number.isFinite(streak) && streak > 0) {
      activeStreaks += 1;
      streakSum += streak;
      for (const [label, threshold] of streakThresholds) {
        if (streak >= threshold) streakCounts[label] += 1;
      }
    }
  }

  const sampledActiveUsers = activeUserSample.size;
  const avgStreak = activeStreaks === 0 ? 0 : Math.round((streakSum / activeStreaks) * 10) / 10;
  const focusResult = results.find((result) => result.questionId === focusQuestionId) ?? results[0] ?? null;
  const todayCompletionRow = completionRows[completionRows.length - 1] ?? null;

  return {
    generatedAt: new Date().toISOString(),
    metrics: {
      totalUsers,
      activeUsers,
      newUsers7d,
      waitlistSignups,
      notificationTokens,
      leaderboardRows,
      answersToday: liveCounters?.total ?? focusResult?.totalAnswers ?? 0,
      predictionsLocked: liveCounters?.total ?? 0,
      dailyCompletersToday: todayCompletionRow?.completers ?? 0,
      returningCompletersToday: todayCompletionRow?.returningCompleters ?? 0,
      returningCompleterPctToday: todayCompletionRow?.returningPct ?? 0,
      avgStreak,
      activeStreaks,
    },
    questions,
    results,
    focusResult,
    liveCounters: liveQuestion ? {
      questionId: liveQuestion.id,
      totalAnswers: liveCounters?.total ?? 0,
      optionCounts: liveOptionCounts,
      optionPcts: liveOptionPcts,
    } : null,
    dailyActivity: [...results]
      .reverse()
      .map((result) => ({
        label: result.dailyKey || result.closedAt?.slice(0, 10) || result.questionId,
        value: result.totalAnswers,
      })),
    completionRows,
    categoryRows: Object.entries(categoryAnswerTotals)
      .sort((a, b) => b[1] - a[1])
      .map(([category, answers]) => ({
        category,
        value: pct(answers, resultAnswerTotal),
        answers,
      })),
    retentionRows: Object.entries(streakCounts).map(([label, value]) => ({
      label,
      value: pct(value, sampledActiveUsers),
    })),
    audience: {
      age: bucketRows(ageBuckets, sampledActiveUsers),
      gender: bucketRows(genderBuckets, sampledActiveUsers),
      country: bucketRows(countryBuckets, sampledActiveUsers).slice(0, 8),
    },
  };
});

export const getAdminAppConfig = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const template = await getRemoteConfig().getTemplate();
  return {
    flags: ADMIN_FEATURE_FLAGS.map((flag) => {
      const value = template.parameters[flag.key]?.defaultValue;
      const rawValue = value && "value" in value ? value.value : undefined;
      return {
        ...flag,
        enabled: remoteConfigBooleanValue(rawValue, flag.defaultValue),
      };
    }),
    version: template.version?.versionNumber ?? null,
    updatedAt: template.version?.updateTime ?? null,
  };
});

export const setAdminFeatureFlag = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const flag = adminFeatureFlagDefinition(request.data?.key);
  if (!flag) {
    throw new HttpsError("invalid-argument", "Feature flag is not supported.");
  }
  if (typeof request.data?.enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "enabled must be a boolean.");
  }
  const enabled = request.data.enabled;
  const remoteConfig = getRemoteConfig();
  const template = await remoteConfig.getTemplate();
  template.parameters[flag.key] = {
    defaultValue: { value: String(enabled) },
    valueType: "BOOLEAN",
    description: flag.description,
  };
  const published = await remoteConfig.publishTemplate(template);
  await db.collection("admin").doc("featureFlagAudit").collection("events").add({
    key: flag.key,
    enabled,
    updatedBy: uid,
    remoteConfigVersion: published.version?.versionNumber ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {
    key: flag.key,
    enabled,
    version: published.version?.versionNumber ?? null,
  };
});

export const closeAndOpenDaily = onSchedule({
  schedule: "0 0 * * *",
  timeZone: EASTERN_TIME_ZONE,
}, async () => {
  const now = Timestamp.now();
  const liveQuestions = await db
    .collection("questions")
    .where("status", "==", "live")
    .where("closeAt", "<=", now)
    .limit(5)
    .get();

  for (const doc of liveQuestions.docs) {
    const result = await closeQuestion(doc.id);
    logger.info("Closed daily question", result);
  }

  const remainingLiveQuestions = await db
    .collection("questions")
    .where("status", "==", "live")
    .limit(5)
    .get();
  const scheduledQuestions = await db
    .collection("questions")
    .where("status", "==", "scheduled")
    .where("publishAt", "<=", now)
    .orderBy("publishAt", "asc")
    .limit(1)
    .get();

  const decision = decideDailyOpen(
    remainingLiveQuestions.docs.map((doc) => doc.id),
    scheduledQuestions.docs.map((doc) => doc.id),
  );
  if (decision.openQuestionId == null) {
    logger.info("Skipped opening daily question", {
      reason: decision.skipReason,
      remainingLiveQuestions: remainingLiveQuestions.docs.map((doc) => doc.id),
    });
    return;
  }

  const nextQuestion = scheduledQuestions.docs.find((doc) => doc.id === decision.openQuestionId);
  if (!nextQuestion) return;
  await nextQuestion.ref.set({
    status: "live",
    openedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  logger.info("Opened daily question", { questionId: nextQuestion.id });
});

export const createInvite = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAppFeature("feature_friends", "Friend invites are currently disabled.");
  const { code } = await createShortLink({
    type: "invite",
    targetId: uid,
    createdBy: uid,
    createInviteDoc: true,
  });
  return {
    code,
    url: `${SHARE_URL}/${code}`,
    shortUrl: `https://rtw.codes/${code}`,
  };
});

export const createShareLink = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAppFeature("feature_result_sharing", "Result sharing is currently disabled.");
  const questionId = assertString(request.data?.questionId, "questionId");
  await requireRevealedResult(questionId, "Only revealed results can be shared.");
  const { code } = await createShortLink({
    type: "result",
    targetId: questionId,
    createdBy: uid,
  });
  return {
    code,
    url: `${SHARE_URL}/${code}`,
    shortUrl: `https://rtw.codes/${code}`,
  };
});

export const acceptInvite = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAppFeature("feature_friends", "Friend invites are currently disabled.");
  const code = assertString(request.data?.code, "code").toUpperCase();
  const linkSnap = await db.collection("links").doc(code).get();
  const link = linkSnap.data() ?? {};
  if (!linkSnap.exists || link.type !== "invite") {
    throw new HttpsError("not-found", "Invite not found.");
  }
  if (shortLinkExpired(timestampDate(link.expiresAt))) {
    throw new HttpsError("deadline-exceeded", "Invite has expired.");
  }
  const inviteSnap = await db.collection("invites").doc(code).get();
  const invite = inviteSnap.data() ?? {};
  if (invite.status != null && invite.status !== "active") {
    throw new HttpsError("failed-precondition", "Invite is no longer active.");
  }
  if (shortLinkExpired(timestampDate(invite.expiresAt))) {
    throw new HttpsError("deadline-exceeded", "Invite has expired.");
  }
  const inviterUid = String(link.targetId ?? "");
  if (!inviterUid || inviterUid === uid) {
    throw new HttpsError("failed-precondition", "Invite cannot be accepted.");
  }

  const [inviterUser, inviteeUser] = await Promise.all([
    getAuth().getUser(inviterUid).catch(() => null),
    getAuth().getUser(uid).catch(() => null),
  ]);
  const [inviterProfile, inviteeProfile] = await Promise.all([
    friendProfileFields(inviterUid, inviterUser?.displayName),
    friendProfileFields(uid, inviteeUser?.displayName),
  ]);
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(db.collection("users").doc(uid).collection("friends").doc(inviterUid), {
    ...inviterProfile,
    status: "active",
    answersShared: false,
    answersSharedByFriend: false,
    createdAt: now,
    updatedAt: now,
    inviteCode: code,
  }, { merge: true });
  batch.set(db.collection("users").doc(inviterUid).collection("friends").doc(uid), {
    ...inviteeProfile,
    status: "active",
    answersShared: false,
    answersSharedByFriend: false,
    createdAt: now,
    updatedAt: now,
    inviteCode: code,
  }, { merge: true });
  batch.set(db.collection("invites").doc(code), {
    acceptedBy: FieldValue.arrayUnion(uid),
    lastAcceptedAt: now,
    status: "active",
  }, { merge: true });
  await batch.commit();
  return { accepted: true, inviterUid };
});

export const resolveShortCode = onCall(callableOptions, async (request) => {
  const code = assertString(request.data?.code, "code").toUpperCase();
  const ref = db.collection("links").doc(code);
  const snap = await ref.get();
  const link = snap.data() ?? {};
  const type = String(link.type ?? "");
  if (!snap.exists || !isShortLinkType(type)) {
    throw new HttpsError("not-found", "Link not found.");
  }
  if (shortLinkExpired(timestampDate(link.expiresAt))) {
    throw new HttpsError("deadline-exceeded", "Link has expired.");
  }
  if (!(await shortLinkFeatureEnabled(type))) {
    throw new HttpsError("failed-precondition", "This link type is currently disabled.");
  }

  const targetId = String(link.targetId ?? "");
  if (type === "result") {
    const state = await readRevealState(targetId);
    if (!targetId || !state.revealed) {
      throw new HttpsError("failed-precondition", "Result is not available.");
    }
  }

  await ref.set({
    counters: {
      opens: FieldValue.increment(1),
      appOpens: FieldValue.increment(1),
    },
    lastOpenedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const route = type === "room"
    ? `/join/${code}`
    : type === "invite"
      ? `/invite/${code}`
      : `/reveal/${encodeURIComponent(targetId)}?code=${encodeURIComponent(code)}`;
  return { code, type, targetId, route };
});

async function friendAnswerComparisonsForUser(uid: string, questionId: string) {
  await requireAppFeature("feature_friends", "Friends are currently disabled.");
  await requireRevealedResult(questionId, "Friend answers are available after reveal.");

  const friendsSnap = await db.collection("users").doc(uid).collection("friends").get();
  const visibleFriends = friendsSnap.docs
    .filter((doc) => {
      const data = doc.data();
      return data.status !== "removed" && data.answersSharedByFriend === true;
    })
    .slice(0, 50);
  if (visibleFriends.length === 0) {
    return { questionId, rows: [] };
  }

  const answerRefs = visibleFriends.map((doc) =>
    db.collection("users").doc(doc.id).collection("answers").doc(questionId),
  );
  const rows: Array<Record<string, unknown>> = [];
  for (let index = 0; index < answerRefs.length; index += 100) {
    const answerSnaps = await db.getAll(...answerRefs.slice(index, index + 100));
    answerSnaps.forEach((answerSnap, offset) => {
      if (!answerSnap.exists) return;
      const answer = answerSnap.data() ?? {};
      if (answer.official !== true) return;
      const friend = visibleFriends[index + offset];
      const friendData = friend.data();
      rows.push({
        uid: friend.id,
        displayName: String(friendData.displayName ?? "Reader"),
        selectedOptionId: String(answer.selectedOptionId ?? ""),
        predictedShare: Number(answer.predictedShare ?? 0),
        readAccuracy: typeof answer.readAccuracy === "number" ? answer.readAccuracy : null,
      });
    });
  }

  rows.sort((a, b) => String(a.displayName).localeCompare(String(b.displayName)));
  return { questionId, rows };
}

export const setFriendAnswerVisibility = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAppFeature("feature_friends", "Friends are currently disabled.");
  const friendUid = assertString(request.data?.friendUid, "friendUid");
  const answersShared = request.data?.answersShared === true;
  if (friendUid === uid) {
    throw new HttpsError("failed-precondition", "Cannot change visibility for yourself.");
  }

  const friendRef = db.collection("users").doc(uid).collection("friends").doc(friendUid);
  const friendSnap = await friendRef.get();
  if (!friendSnap.exists || friendSnap.data()?.status === "removed") {
    throw new HttpsError("not-found", "Friend not found.");
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(friendRef, {
    answersShared,
    updatedAt: now,
  }, { merge: true });
  batch.set(db.collection("users").doc(friendUid).collection("friends").doc(uid), {
    answersSharedByFriend: answersShared,
    updatedAt: now,
  }, { merge: true });
  await batch.commit();
  return { friendUid, answersShared };
});

export const removeFriend = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAppFeature("feature_friends", "Friends are currently disabled.");
  const friendUid = assertString(request.data?.friendUid, "friendUid");
  if (friendUid === uid) {
    throw new HttpsError("failed-precondition", "Cannot remove yourself.");
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(db.collection("users").doc(uid).collection("friends").doc(friendUid), {
    status: "removed",
    removedAt: now,
    updatedAt: now,
  }, { merge: true });
  batch.set(db.collection("users").doc(friendUid).collection("friends").doc(uid), {
    status: "removed",
    removedAt: now,
    updatedAt: now,
  }, { merge: true });
  await batch.commit();
  return { removed: true, friendUid };
});

export const getLeaderboard = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  if (request.data?.mode === "friendAnswerComparisons") {
    const questionId = assertString(request.data?.questionId, "questionId");
    return friendAnswerComparisonsForUser(uid, questionId);
  }

  const limit = Math.min(Number(request.data?.limit ?? 50), LEADERBOARD_LIMIT);
  const rowsSnap = await db
    .collection("leaderboards")
    .doc("global")
    .collection("rows")
    .orderBy("rank", "asc")
    .limit(limit)
    .get();
  return {
    boardId: "global",
    rows: rowsSnap.docs.map((doc) => doc.data()),
  };
});

export const recomputeLeaderboardsNow = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  return recomputeGlobalLeaderboard();
});

export const recomputeLeaderboards = onSchedule({
  schedule: "15 * * * *",
  timeZone: EASTERN_TIME_ZONE,
}, async () => {
  const result = await recomputeGlobalLeaderboard();
  logger.info("Recomputed leaderboards", result);
});

export const sendDailyNotifications = onSchedule({
  schedule: "0 8 * * *",
  timeZone: EASTERN_TIME_ZONE,
  secrets: [postmarkServerToken],
}, async () => {
  const todayKey = dailyKeyForEasternDate(new Date());
  const tokens = await activeNotificationTokens();
  const result = await sendNotificationToTokens(
    tokens,
    dailyNotificationPayload("daily_room_ready"),
  );
  const emailResult = await sendDailyHabitEmailsToUsersWithoutPush(todayKey);

  logger.info("Sent daily notifications", {
    todayKey,
    ...result,
    email: emailResult,
  });
});

export const sendRevealReadyNotifications = onSchedule({
  schedule: "10 0 * * *",
  timeZone: EASTERN_TIME_ZONE,
}, async () => {
  logger.info("Skipped separate reveal-ready notifications; daily room-ready reminder covers reveals.");
});

export const sendVerificationEmail = onCall(emailCallableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const authUser = await getAuth().getUser(uid);
  const email = String(authUser.email ?? "").trim().toLowerCase();
  if (!isValidEmail(email)) {
    throw new HttpsError("failed-precondition", "Add an email address before verifying.");
  }
  if (authUser.emailVerified) {
    return { sent: false, alreadyVerified: true };
  }

  try {
    const link = await getAuth().generateEmailVerificationLink(email, {
      url: `${APP_URL}/rooms`,
      handleCodeInApp: false,
    });
    const profileSnap = await db.collection("users").doc(uid).get();
    const profile = profileSnap.data() ?? {};
    const result = await sendPostmarkEmail(verificationEmail({
      to: email,
      displayName: String(profile.displayName ?? authUser.displayName ?? "Reader"),
      verificationUrl: link,
    }));
    await db.collection("users").doc(uid).set({
      email,
      verificationEmailSentAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.info("Sent verification email", { uid, messageId: result.MessageID ?? null });
    return { sent: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes("TOO_MANY_ATTEMPTS_TRY_LATER")) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many verification emails were requested. Try again later.",
      );
    }
    if (error instanceof PostmarkSendError) {
      logger.warn("Verification email provider rejected send", {
        uid,
        status: error.status,
        message: error.postmarkMessage,
      });
      if (error.status === 422 && error.postmarkMessage.includes("pending approval")) {
        throw new HttpsError(
          "failed-precondition",
          "Email delivery is still being approved for external addresses.",
        );
      }
      throw new HttpsError(
        "unavailable",
        "Verification email delivery is temporarily unavailable.",
      );
    }
    logger.error("Verification email failed", { uid, error: message });
    throw new HttpsError(
      "internal",
      "Verification email could not be sent. Try again later.",
    );
  }
});

export const submitFeedback = onCall(feedbackCallableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const message = assertFeedbackMessage(request.data?.message);
  const source = normalizeFeedbackSource(request.data?.source);
  const authUser = await getAuth().getUser(uid);
  const userRef = db.collection("users").doc(uid);
  const feedbackRef = db.collection("feedback").doc();
  let displayName = "Reader";
  let email = "";

  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const userData = userSnap.data() ?? {};
    const lastFeedbackAt = userData.lastFeedbackAt;
    if (
      lastFeedbackAt instanceof Timestamp &&
      Date.now() - lastFeedbackAt.toMillis() < FEEDBACK_COOLDOWN_MS
    ) {
      throw new HttpsError(
        "resource-exhausted",
        "Feedback was just sent. Try again in a minute.",
      );
    }
    displayName = String(userData.displayName ?? authUser.displayName ?? "Reader").trim() || "Reader";
    email = String(userData.email ?? authUser.email ?? "").trim().toLowerCase();
    tx.set(feedbackRef, {
      uid,
      displayName,
      email: email || null,
      message,
      source,
      emailStatus: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(userRef, {
      lastFeedbackAt: FieldValue.serverTimestamp(),
      feedbackCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  try {
    const result = await sendPostmarkEmail(feedbackEmail({
      to: ALLOWED_ADMIN_EMAIL,
      displayName,
      email,
      uid,
      message,
      source,
    }));
    await feedbackRef.set({
      emailStatus: "sent",
      emailSentAt: FieldValue.serverTimestamp(),
      emailMessageId: result.MessageID ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.info("Sent feedback email", {
      uid,
      feedbackId: feedbackRef.id,
      messageId: result.MessageID ?? null,
    });
    return { saved: true, emailed: true };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    await feedbackRef.set({
      emailStatus: "failed",
      emailError: errorMessage.slice(0, 500),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.warn("Feedback saved but email failed", {
      uid,
      feedbackId: feedbackRef.id,
      error: errorMessage,
    });
    return { saved: true, emailed: false };
  }
});

export const submitSupportContact = onRequest({
  cors: true,
  secrets: [postmarkServerToken],
}, async (req, res) => {
  res.set("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.set("Allow", "POST");
    res.status(405).json({ error: "method-not-allowed" });
    return;
  }

  try {
    const body = typeof req.body === "object" && req.body !== null
      ? req.body as Record<string, unknown>
      : {};

    // Honeypot for basic bot noise. Pretend success without sending.
    if (typeof body.company === "string" && body.company.trim().length > 0) {
      res.json({ ok: true, emailed: true });
      return;
    }

    const name = assertSupportName(body.name);
    const email = normalizeEmail(body.email);
    const message = assertSupportMessage(body.message);
    const ipHash = requestIpHash(req);
    const emailHash = createHash("sha256").update(email).digest("hex");
    const cooldownRef = db.collection("supportContactCooldowns").doc(
      createHash("sha256").update(`${emailHash}:${ipHash}`).digest("hex"),
    );
    const contactRef = db.collection("supportContacts").doc();

    await db.runTransaction(async (tx) => {
      const cooldownSnap = await tx.get(cooldownRef);
      const lastContactAt = cooldownSnap.data()?.lastContactAt;
      if (
        lastContactAt instanceof Timestamp &&
        Date.now() - lastContactAt.toMillis() < SUPPORT_CONTACT_COOLDOWN_MS
      ) {
        throw new HttpsError(
          "resource-exhausted",
          "That message was just sent. Try again in a minute.",
        );
      }

      tx.set(contactRef, {
        name,
        email,
        message,
        source: "support-page",
        ipHash,
        userAgent: String(req.header("user-agent") ?? "").slice(0, 500) || null,
        emailStatus: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(cooldownRef, {
        emailHash,
        ipHash,
        lastContactAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    const result = await sendPostmarkEmail(supportContactEmail({
      to: ALLOWED_ADMIN_EMAIL,
      name,
      email,
      message,
      contactId: contactRef.id,
    }));
    await contactRef.set({
      emailStatus: "sent",
      emailSentAt: FieldValue.serverTimestamp(),
      emailMessageId: result.MessageID ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.info("Sent support contact email", {
      contactId: contactRef.id,
      messageId: result.MessageID ?? null,
    });
    res.json({ ok: true, emailed: true, contactId: contactRef.id });
  } catch (error) {
    const code = error instanceof HttpsError ? error.code : "internal";
    const message = error instanceof HttpsError
      ? error.message
      : "Support message could not be sent. Try again later.";
    const status = code === "invalid-argument"
      ? 400
      : code === "resource-exhausted"
        ? 429
        : 500;
    logger.warn("Support contact failed", {
      code,
      error: error instanceof Error ? error.message : String(error),
    });
    res.status(status).json({ error: code, message });
  }
});

async function sendNewUserNotification(
  uid: string,
  data: DocumentData,
): Promise<{ sent: boolean; skipped?: boolean; saved?: boolean }> {
  const authUser = await getAuth().getUser(uid);
  const notificationRef = db.collection("accountNotifications").doc(uid);
  const accountCreatedAt = authUser.metadata.creationTime ?? new Date().toISOString();
  const accountCreatedAtMs = Date.parse(accountCreatedAt);
  const accountAgeMs = Number.isFinite(accountCreatedAtMs)
    ? Date.now() - accountCreatedAtMs
    : 0;

  try {
    await notificationRef.create({
      uid,
      emailStatus: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const code = (error as { code?: unknown }).code;
    if (code === 6 || code === "already-exists") {
      logger.info("Skipped duplicate new user notification", { uid });
      return { sent: false, skipped: true };
    }
    throw error;
  }

  if (accountAgeMs > 7 * 24 * 60 * 60 * 1000) {
    await notificationRef.set({
      emailStatus: "skipped",
      skipReason: "account-too-old",
      accountCreatedAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.info("Skipped new user email for older account", { uid, accountCreatedAt });
    return { sent: false, skipped: true };
  }

  const displayName = String(data.displayName ?? authUser.displayName ?? "Reader").trim() || "Reader";
  const email = String(data.email ?? authUser.email ?? "").trim().toLowerCase();
  const providers = authUser.providerData.map((provider) => provider.providerId);
  const createdAt = timestampToIso(data.createdAt ?? accountCreatedAt);

  await notificationRef.set({
    displayName,
    email: email || null,
    providers,
    accountCreatedAt: createdAt,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  try {
    const result = await sendPostmarkEmail(newUserEmail({
      to: ALLOWED_ADMIN_EMAIL,
      displayName,
      email,
      uid,
      providers,
      createdAt,
    }));
    await notificationRef.set({
      emailStatus: "sent",
      emailSentAt: FieldValue.serverTimestamp(),
      emailMessageId: result.MessageID ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.info("Sent new user email", {
      uid,
      messageId: result.MessageID ?? null,
    });
    return { sent: true };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    await notificationRef.set({
      emailStatus: "failed",
      emailError: errorMessage.slice(0, 500),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.warn("New user notification email failed", {
      uid,
      error: errorMessage,
    });
    return { sent: false, saved: true };
  }
}

export const notifyNewUserOnProfileCreate = onDocumentCreated(
  {
    document: "users/{uid}",
    secrets: [postmarkServerToken],
  },
  async (event) => {
    const uid = event.params.uid;
    const data = event.data?.data() ?? {};
    await sendNewUserNotification(uid, data);
  },
);

export const notifyNewUser = onCall(feedbackCallableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const userSnap = await db.collection("users").doc(uid).get();
  return sendNewUserNotification(uid, userSnap.data() ?? {});
});

export const sendBroadcastNotification = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const title = assertNotificationText(request.data?.title, "title", 80);
  const body = assertNotificationText(request.data?.body, "body", 180);
  const route = assertNotificationRoute(request.data?.route);
  const audience = normalizeBroadcastAudience(request.data?.audience);
  const requestedLimit = Number(request.data?.limit ?? 5000);
  const safeLimit = Math.max(1, Math.min(10000, Number.isFinite(requestedLimit) ? requestedLimit : 5000));
  const tokens = await notificationTokensForAudience(audience, safeLimit);
  const result = await sendNotificationToTokens(tokens, {
    title,
    body,
    route,
    type: "admin_broadcast",
  });
  const campaignRef = await db.collection("notificationCampaigns").add({
    createdBy: uid,
    title,
    body,
    route,
    audience,
    tokenLimit: safeLimit,
    ...result,
    createdAt: FieldValue.serverTimestamp(),
  });
  logger.info("Sent admin broadcast notification", {
    campaignId: campaignRef.id,
    audience,
    ...result,
  });
  return {
    campaignId: campaignRef.id,
    audience,
    ...result,
  };
});

export const resolveShortLink = onRequest(async (req, res) => {
  const code = req.path.split("/").filter(Boolean)[0] ?? "";
  if (!code) {
    res.redirect(302, MARKETING_URL);
    return;
  }

  const ref = db.collection("links").doc(code.toUpperCase());
  const snap = await ref.get();
  if (!snap.exists) {
    res.redirect(302, MARKETING_URL);
    return;
  }

  const link = snap.data() ?? {};
  const type = String(link.type ?? "");
  if (!isShortLinkType(type) || shortLinkExpired(timestampDate(link.expiresAt))) {
    res.redirect(302, MARKETING_URL);
    return;
  }
  if (!(await shortLinkFeatureEnabled(type))) {
    res.redirect(302, MARKETING_URL);
    return;
  }

  const targetId = String(link.targetId ?? "");
  if (type === "result") {
    const state = await readRevealState(targetId);
    if (!targetId || !state.revealed) {
      res.redirect(302, MARKETING_URL);
      return;
    }
  }

  await ref.set({
    counters: {
      opens: FieldValue.increment(1),
    },
    lastOpenedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const encodedTargetId = encodeURIComponent(targetId);
  const destination = type === "room"
    ? `${APP_URL}/join/${code}`
    : type === "invite"
      ? `${APP_URL}/invite/${code}`
      : `${APP_URL}/reveal/${encodedTargetId}?code=${code}`;
  res.redirect(302, destination);
});

export const appleAppSiteAssociation = onRequest((_, res) => {
  const teamId = process.env.APPLE_TEAM_ID ?? "TEAMID";
  const bundleId = process.env.IOS_BUNDLE_ID ?? "today.readtheworld.app";
  res.setHeader("Content-Type", "application/json");
  res.status(200).send({
    applinks: {
      apps: [],
      details: [
        {
          appIDs: [`${teamId}.${bundleId}`],
          components: [
            { "/": "/*", comment: "Read the World share and invite links" },
          ],
        },
      ],
    },
  });
});

export const androidAssetLinks = onRequest((_, res) => {
  const enabled = (process.env.ANDROID_APP_LINKS_ENABLED ?? "true").toLowerCase() !== "false";
  if (!enabled) {
    res.setHeader("Content-Type", "application/json");
    res.status(200).send([]);
    return;
  }

  const packageName = process.env.ANDROID_PACKAGE_NAME ?? "today.readtheworld.app";
  const fingerprints = (process.env.ANDROID_SHA256_CERT_FINGERPRINTS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  res.setHeader("Content-Type", "application/json");
  res.status(200).send([
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: packageName,
        sha256_cert_fingerprints: fingerprints,
      },
    },
  ]);
});

export const upsertQuestion = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const questionId = assertString(request.data?.questionId, "questionId");
  const prompt = assertString(request.data?.prompt, "prompt");
  const category = assertString(request.data?.category, "category").toUpperCase();
  let options: QuestionOption[];
  let status: QuestionStatus;
  let dailyKey: string | null;
  let publishAt: Date | null;
  let closeAt: Date | null;
  try {
    options = normalizeQuestionOptions(request.data?.options);
    status = normalizeQuestionStatus(request.data?.status ?? "draft");
    dailyKey = normalizeDailyKey(request.data?.dailyKey);
    publishAt = parseQuestionDate(request.data?.publishAt, "publishAt");
    closeAt = parseQuestionDate(request.data?.closeAt, "closeAt");
    validateQuestionSchedule({ status, dailyKey, publishAt, closeAt });
  } catch (error) {
    mapQuestionValidationError(error);
  }

  if (status === "live") {
    await assertNoOtherLiveQuestion(questionId);
  }

  await db.collection("questions").doc(questionId).set({
    prompt,
    category,
    options,
    type: options.length === 2 ? "binary" : "choice",
    status,
    dailyKey,
    publishAt: publishAt ? Timestamp.fromDate(publishAt) : null,
    closeAt: closeAt ? Timestamp.fromDate(closeAt) : null,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { questionId, saved: true };
});

export const closeQuestionNow = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const questionId = assertString(request.data?.questionId, "questionId");
  return closeQuestion(questionId, true);
});

export const recomputeQuestion = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const questionId = assertString(request.data?.questionId, "questionId");
  return closeQuestion(questionId, true);
});

export const seedInitialQuestions = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);

  let seedQuestions;
  try {
    seedQuestions = buildProductionQuestionSeed({
      todayDailyKey: normalizeDailyKey(request.data?.todayDailyKey ?? request.data?.startDailyKey),
      historyDays: request.data?.historyDays == null ? undefined : Number(request.data.historyDays),
      futureDays: request.data?.futureDays == null ? undefined : Number(request.data.futureDays),
    });
  } catch (error) {
    mapQuestionValidationError(error);
  }

  const liveQuestionId = seedQuestions.find((question) => question.status === "live")?.id ?? null;
  const liveQuestions = await db
    .collection("questions")
    .where("status", "==", "live")
    .limit(5)
    .get();
  const conflictingLiveQuestions = liveQuestions.docs
    .map((doc) => doc.id)
    .filter((questionId) => questionId !== liveQuestionId);
  if (conflictingLiveQuestions.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      "A live question already exists. Close it before seeding initial questions.",
    );
  }

  const questionRefs = seedQuestions.map((question) => db.collection("questions").doc(question.id));
  const resultRefs = seedQuestions.map((question) =>
    question.result ? db.collection("dailyResults").doc(question.id) : null,
  );
  const existingQuestions = await Promise.all(questionRefs.map((ref) => ref.get()));
  const existingResults = await Promise.all(
    resultRefs.map((ref) => ref == null ? Promise.resolve(null) : ref.get()),
  );
  const batch = db.batch();
  let seededQuestions = 0;
  let skippedQuestions = 0;
  let seededResults = 0;
  let skippedResults = 0;
  seedQuestions.forEach((question, index) => {
    if (existingQuestions[index]?.exists) {
      skippedQuestions += 1;
    } else {
      seededQuestions += 1;
      batch.set(questionRefs[index], {
        category: question.category,
        prompt: question.prompt,
        options: question.options,
        type: question.type,
        status: question.status,
        dailyKey: question.dailyKey,
        publishAt: Timestamp.fromDate(question.publishAt),
        closeAt: Timestamp.fromDate(question.closeAt),
        totalAnswers: question.result?.totalAnswers ?? 0,
        closedAt: question.result ? Timestamp.fromDate(question.result.closedAt) : null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const resultRef = resultRefs[index];
    const result = question.result;
    if (resultRef == null || result == null) return;
    if (existingResults[index]?.exists) {
      skippedResults += 1;
      return;
    }
    seededResults += 1;
    batch.set(resultRef, {
      questionId: question.id,
      dailyKey: question.dailyKey,
      category: question.category,
      prompt: question.prompt,
      status: "closed",
      options: question.options,
      optionCounts: result.optionCounts,
      optionPcts: result.optionPcts,
      totalAnswers: result.totalAnswers,
      countedTowardScore: result.countedTowardScore,
      closedAt: Timestamp.fromDate(result.closedAt),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  if (seededQuestions > 0 || seededResults > 0) {
    await batch.commit();
  }
  return {
    seededQuestions,
    skippedQuestions,
    seededResults,
    skippedResults,
    totalQuestions: seedQuestions.length,
    historyDays: seedQuestions.filter((question) => question.status === "closed").length,
    futureDays: seedQuestions.filter((question) => question.status === "scheduled").length,
    todayDailyKey: seedQuestions.find((question) => question.status === "live")?.dailyKey ?? null,
    liveQuestionId,
  };
});

// ════════════════════════════════════════════════════════════════════════════
// v2 — ROOMS (docs/v2-implementation-spec.md)
// All room mutations flow through callables; Firestore rules deny client
// writes so these handlers are the single source of invariants.
// ════════════════════════════════════════════════════════════════════════════

type RoomDayQuestion = {
  qid: string;
  prompt: string;
  optA: string;
  optB: string;
  tag: string;
  shape: string;
  tier: string;
  custom: boolean;
  authorUid: string | null;
  authorName: string | null;
  pulled: boolean;
  threshold: number | null;
};

type RoomPick = {
  qid: string;
  side: "a" | "b";
  prediction: number | null;
};

const WORLD_ROOM_NAME = "The World";
const ROOM_MEMBER_SEEN_SCAN_CAP = 25;

function roomRef(roomId: string) {
  return db.collection("rooms").doc(roomId);
}

function roomDayRef(roomId: string, dailyKey: string) {
  return roomRef(roomId).collection("days").doc(dailyKey);
}

async function removeAccountRoomDayData(
  uid: string,
  dayRef: DocumentReference,
): Promise<void> {
  const answerRef = dayRef.collection("answers").doc(uid);
  await db.runTransaction(async (tx) => {
    const [daySnap, answerSnap] = await Promise.all([
      tx.get(dayRef),
      tx.get(answerRef),
    ]);
    if (!daySnap.exists) return;

    const day = daySnap.data() ?? {};
    const questions = Array.isArray(day.questions)
      ? (day.questions as RoomDayQuestion[])
      : [];
    const sanitizedQuestions = questions.map((question) =>
      question.authorUid === uid
        ? { ...question, authorUid: null, authorName: "Deleted user" }
        : question);
    const updates: Record<string, unknown> = {};
    if (sanitizedQuestions.some((question, index) => question !== questions[index])) {
      updates.questions = sanitizedQuestions;
    }

    if (answerSnap.exists) {
      const answer = answerSnap.data() ?? {};
      const picks = Array.isArray(answer.picks)
        ? (answer.picks as Array<Record<string, unknown>>)
        : [];
      const answerCounts = { ...((day.answerCounts ?? {}) as Record<string, number>) };
      for (const pick of picks) {
        const qid = typeof pick.qid === "string" ? pick.qid : "";
        if (!qid) continue;
        answerCounts[qid] = Math.max(0, Number(answerCounts[qid] ?? 0) - 1);
      }
      updates.answerCount = Math.max(0, Number(day.answerCount ?? 0) - 1);
      updates.answerCounts = answerCounts;
      tx.delete(answerRef);
    }
    if (Object.keys(updates).length > 0) {
      tx.set(dayRef, {
        ...updates,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });
}

async function removeAccountFromRoom(uid: string, roomId: string): Promise<void> {
  const targetRoomRef = roomRef(roomId);
  const userMembershipRef = db.collection("users").doc(uid)
    .collection("memberships").doc(roomId);
  const [roomSnap, membersSnap, daysSnap, authoredQueueSnap] = await Promise.all([
    targetRoomRef.get(),
    targetRoomRef.collection("members").get(),
    targetRoomRef.collection("days").get(),
    targetRoomRef.collection("queue").where("authorUid", "==", uid).get(),
  ]);
  if (!roomSnap.exists) {
    await userMembershipRef.delete();
    return;
  }

  const room = roomSnap.data() ?? {};
  const memberDoc = membersSnap.docs.find((doc) => doc.id === uid);
  const member = memberDoc?.data() ?? {};
  const others = membersSnap.docs.filter((doc) => doc.id !== uid);
  if (room.isWorld !== true && memberDoc && others.length === 0) {
    const batch = db.batch();
    batch.delete(userMembershipRef);
    const inviteCode = typeof room.inviteCode === "string" ? room.inviteCode : "";
    if (inviteCode) batch.delete(db.collection("links").doc(inviteCode));
    await batch.commit();
    await db.recursiveDelete(targetRoomRef);
    return;
  }

  for (const dayDoc of daysSnap.docs) {
    await removeAccountRoomDayData(uid, dayDoc.ref);
  }

  const writes: Array<(batch: WriteBatch) => void> = [];
  writes.push((batch) => batch.delete(userMembershipRef));
  if (memberDoc) {
    writes.push((batch) => batch.delete(memberDoc.ref));
    writes.push((batch) => batch.set(targetRoomRef, {
      memberCount: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }
  authoredQueueSnap.docs.forEach((doc) => {
    writes.push((batch) => batch.delete(doc.ref));
  });

  const deletingCreator = member.role === "creator" || room.createdBy === uid;
  if (deletingCreator && others.length > 0) {
    const successor = [...others].sort((a, b) => {
      const aJoined = timestampDate(a.data().joinedAt)?.getTime() ?? 0;
      const bJoined = timestampDate(b.data().joinedAt)?.getTime() ?? 0;
      return aJoined - bJoined;
    })[0];
    writes.push((batch) => batch.set(successor.ref, { role: "creator" }, { merge: true }));
    writes.push((batch) => batch.set(targetRoomRef, {
      createdBy: successor.id,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
    const inviteCode = typeof room.inviteCode === "string" ? room.inviteCode : "";
    if (inviteCode) {
      writes.push((batch) => batch.set(db.collection("links").doc(inviteCode), {
        createdBy: successor.id,
      }, { merge: true }));
    }
  }
  await commitBatchedWrites(writes);
}

async function roomDislikedQuestionIds(
  roomId: string,
  room: DocumentData,
): Promise<Set<string>> {
  if (room.isWorld === true) return new Set();
  const snap = await roomRef(roomId).collection("questionDislikes")
    .where("count", ">", 0)
    .get();
  return new Set(snap.docs.map((doc) => doc.id));
}

async function userDislikedQuestionIds(uid: string): Promise<string[]> {
  const userSnap = await db.collection("users").doc(uid).get();
  const disliked = userSnap.data()?.dislikedQuestionIds;
  return Array.isArray(disliked) ? disliked.map(String) : [];
}

async function applyUserDislikesToRoom(
  uid: string,
  roomId: string,
  delta: 1 | -1,
): Promise<void> {
  if (roomId === WORLD_ROOM_ID) return;
  const dislikedQuestionIds = await userDislikedQuestionIds(uid);
  if (dislikedQuestionIds.length === 0) return;
  await commitBatchedWrites(dislikedQuestionIds.map((qid) => (batch) => {
    batch.set(roomRef(roomId).collection("questionDislikes").doc(qid), {
      qid,
      count: FieldValue.increment(delta),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }));
}

async function applyQuestionDislikeDeltaToMemberRooms(
  uid: string,
  qid: string,
  delta: number,
): Promise<void> {
  if (delta === 0) return;
  const membershipsSnap = await db.collection("users").doc(uid)
    .collection("memberships")
    .get();
  const roomIds = membershipsSnap.docs
    .map((doc) => String(doc.data().roomId ?? doc.id))
    .filter((roomId) => roomId !== WORLD_ROOM_ID);
  await commitBatchedWrites(roomIds.map((roomId) => (batch) => {
    batch.set(roomRef(roomId).collection("questionDislikes").doc(qid), {
      qid,
      count: FieldValue.increment(delta),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }));
}

function assertRoomId(value: unknown): string {
  const roomId = assertString(value, "roomId");
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(roomId)) {
    throw new HttpsError("invalid-argument", "roomId is invalid.");
  }
  return roomId;
}

function mapRoomValidationError(error: unknown): never {
  if (error instanceof RoomValidationError || error instanceof BankValidationError) {
    throw new HttpsError("invalid-argument", error.message);
  }
  throw error;
}

async function requireRoomAndMember(
  roomId: string,
  uid: string,
): Promise<{ room: DocumentData; member: DocumentData }> {
  const [roomSnap, memberSnap] = await db.getAll(
    roomRef(roomId),
    roomRef(roomId).collection("members").doc(uid),
  );
  if (!roomSnap.exists) {
    throw new HttpsError("not-found", "Room not found.");
  }
  if (!memberSnap.exists || memberSnap.data()?.status === "removed") {
    throw new HttpsError("permission-denied", "You are not a member of this room.");
  }
  return { room: roomSnap.data() ?? {}, member: memberSnap.data() ?? {} };
}

async function requireRoomCreator(roomId: string, uid: string): Promise<DocumentData> {
  const { room, member } = await requireRoomAndMember(roomId, uid);
  if (member.role !== "creator") {
    throw new HttpsError("permission-denied", "Only the room creator can do this.");
  }
  return room;
}

async function displayNameForUid(uid: string): Promise<string> {
  const snap = await db.collection("users").doc(uid).get();
  const name = snap.data()?.displayName;
  return typeof name === "string" && name.trim().length > 0 ? name.trim() : "Reader";
}

async function ensureWorldRoom(): Promise<void> {
  const snap = await roomRef(WORLD_ROOM_ID).get();
  if (snap.exists) return;
  await roomRef(WORLD_ROOM_ID).set({
    name: WORLD_ROOM_NAME,
    color: "oklch(0.40 0.11 256)",
    tier: "normal",
    cats: ["All"],
    customEnabled: false,
    revealAnswersDefault: false,
    createdBy: "system",
    isWorld: true,
    worldGoal: WORLD_PLAYER_GOAL,
    memberCount: 0,
    usedQuestionIds: [],
    inviteCode: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function bankCandidates(): Promise<CandidateQuestion[]> {
  const snap = await db.collection("questionBank").where("active", "==", true).get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      prompt: String(data.prompt ?? ""),
      optA: String(data.optA ?? "Yes"),
      optB: String(data.optB ?? "No"),
      tags: Array.isArray(data.tags) ? data.tags.map(String) : [],
      tier: (data.tier ?? "normal") as BankTier,
      shape: (data.shape ?? "TASTE") as BankShape,
      timesUsed: Number(data.timesUsed ?? 0),
    };
  }).filter((candidate) => candidate.prompt.length > 0);
}

function fallbackPartyCandidates(tier: BankTier | null): CandidateQuestion[] {
  const fallbackTier: BankTier = tier === "work-safe" ? "work-safe" : "normal";
  return buildProductionQuestionSeed({ historyDays: 0, futureDays: 80 })
    .filter((question) => question.options.length >= 2)
    .map((question) => ({
      id: bankQuestionIdForPrompt(question.prompt),
      prompt: question.prompt,
      optA: question.options[0].label,
      optB: question.options[1].label,
      tags: [question.category],
      tier: fallbackTier,
      shape: "TASTE" as BankShape,
      timesUsed: 0,
    }));
}

function weightedPartyPool(
  candidates: CandidateQuestion[],
  likedQuestionIds: Set<string>,
): CandidateQuestion[] {
  const remaining = [...candidates];
  const ordered: CandidateQuestion[] = [];
  while (remaining.length > 0) {
    const totalWeight = remaining.reduce(
      (sum, candidate) => sum + (likedQuestionIds.has(candidate.id) ? 1.18 : 1),
      0,
    );
    let pick = Math.random() * totalWeight;
    let index = 0;
    for (; index < remaining.length; index++) {
      pick -= likedQuestionIds.has(remaining[index].id) ? 1.18 : 1;
      if (pick <= 0) break;
    }
    ordered.push(remaining.splice(Math.min(index, remaining.length - 1), 1)[0]);
  }
  return ordered;
}

function dayQuestionFromCandidate(candidate: CandidateQuestion): RoomDayQuestion {
  return {
    qid: candidate.id,
    prompt: candidate.prompt,
    optA: candidate.optA,
    optB: candidate.optB,
    tag: candidate.tags[0] ?? "Everyday",
    shape: candidate.shape,
    tier: candidate.tier,
    custom: false,
    authorUid: null,
    authorName: null,
    pulled: false,
    threshold: null,
  };
}

/**
 * Assigns a room's daily set: dynamic custom-queue injection first
 * (1-4 queued → 1, 5-9 → 2, 10+ → 3), bank selection for the rest.
 * Safe to call repeatedly — no-ops if the day doc already exists.
 */
async function assembleRoomDay(
  roomId: string,
  room: DocumentData,
  dailyKey: string,
): Promise<boolean> {
  const dayRef = roomDayRef(roomId, dailyKey);
  const existing = await dayRef.get();
  if (existing.exists) {
    const status = existing.data()?.status;
    if (status === "scheduled") {
      await dayRef.set({ status: "live", activatedAt: FieldValue.serverTimestamp() }, { merge: true });
      const questions = Array.isArray(existing.data()?.questions)
        ? existing.data()?.questions as RoomDayQuestion[]
        : [];
      const roomUpdates: Record<string, unknown> = {
        currentDailyKey: dailyKey,
        updatedAt: FieldValue.serverTimestamp(),
      };
      const bankQids = questions
        .filter((question) => !question.custom && typeof question.qid === "string" && question.qid.length > 0)
        .map((question) => question.qid);
      if (bankQids.length > 0) {
        roomUpdates.usedQuestionIds = FieldValue.arrayUnion(...bankQids);
      }
      await roomRef(roomId).set(roomUpdates, { merge: true });
      return true;
    }
    return false;
  }

  const questions: RoomDayQuestion[] = [];
  const usedQueueRefs: DocumentReference[] = [];

  if (room.customEnabled !== false && room.isWorld !== true) {
    const queueSnap = await roomRef(roomId).collection("queue")
      .orderBy("createdAt", "asc")
      .get();
    const customCount = Math.min(
      customInjectionCount(queueSnap.size),
      ROOM_QUESTIONS_PER_DAY,
    );
    for (const doc of queueSnap.docs.slice(0, customCount)) {
      const data = doc.data();
      questions.push({
        qid: `custom-${doc.id}`,
        prompt: String(data.text ?? ""),
        optA: String(data.optA ?? "Yes"),
        optB: String(data.optB ?? "No"),
        tag: "Custom",
        shape: "CUSTOM",
        tier: String(room.tier ?? "normal"),
        custom: true,
        authorUid: String(data.authorUid ?? ""),
        authorName: String(data.authorName ?? "A member"),
        pulled: false,
        threshold: null,
      });
      usedQueueRefs.push(doc.ref);
    }
  }

  const bankCount = ROOM_QUESTIONS_PER_DAY - questions.length;
  if (bankCount > 0) {
    const membersSnap = await roomRef(roomId).collection("members").get();
    const memberUids = membersSnap.docs.map((doc) => doc.id);
    const seenMemberUids = new Set(memberUids.slice(0, ROOM_MEMBER_SEEN_SCAN_CAP));
    const seenByMemberIds = new Set<string>();
    const dislikedByMemberIds = await roomDislikedQuestionIds(roomId, room);
    for (const chunk of chunkArray(Array.from(seenMemberUids), 50)) {
      const userSnaps = await db.getAll(
        ...chunk.map((uid) => db.collection("users").doc(uid)),
      );
      for (const snap of userSnaps) {
        const seen = snap.data()?.seenQuestionIds;
        if (Array.isArray(seen)) seen.forEach((qid) => seenByMemberIds.add(String(qid)));
      }
    }

    const picked = selectDailyQuestions({
      roomId,
      dailyKey,
      roomTier: (room.tier ?? "normal") as BankTier,
      roomCats: Array.isArray(room.cats) ? room.cats.map(String) : ["All"],
      candidates: await bankCandidates(),
      usedQuestionIds: new Set(
        Array.isArray(room.usedQuestionIds) ? room.usedQuestionIds.map(String) : [],
      ),
      seenByMemberIds,
      dislikedByMemberIds,
      count: bankCount,
    });
    if (picked.length < bankCount) {
      logger.warn("Question bank ran short for room", {
        roomId,
        dailyKey,
        requested: bankCount,
        picked: picked.length,
      });
    }
    picked.forEach((candidate) => questions.push(dayQuestionFromCandidate(candidate)));

    const bankBatch = db.batch();
    picked.forEach((candidate) => {
      bankBatch.set(db.collection("questionBank").doc(candidate.id), {
        timesUsed: FieldValue.increment(1),
        lastUsedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    memberUids.forEach((uid) => {
      bankBatch.set(db.collection("users").doc(uid), {
        seenQuestionIds: FieldValue.arrayUnion(...picked.map((candidate) => candidate.id)),
      }, { merge: true });
    });
    if (picked.length > 0) await bankBatch.commit();
  }

  if (questions.length === 0) {
    logger.warn("No questions available for room day", { roomId, dailyKey });
    return false;
  }

  await dayRef.set({
    dailyKey,
    status: "live",
    questions,
    answerCount: 0,
    answerCounts: {},
    createdAt: FieldValue.serverTimestamp(),
  });
  const roomUpdates: Record<string, unknown> = {
    currentDailyKey: dailyKey,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const bankQids = questions.filter((question) => !question.custom).map((question) => question.qid);
  if (bankQids.length > 0) {
    roomUpdates.usedQuestionIds = FieldValue.arrayUnion(...bankQids);
  }
  await roomRef(roomId).set(roomUpdates, { merge: true });
  if (usedQueueRefs.length > 0) {
    const queueBatch = db.batch();
    usedQueueRefs.forEach((ref) => queueBatch.delete(ref));
    await queueBatch.commit();
  }
  return true;
}

/**
 * Closes a room day: per-member actuals are "share of the *other* answering
 * members who matched your side" (the prototype's prompt), accuracy via the
 * existing formula, deltas ranked within the room, streak preserved from lock.
 */
async function closeRoomDay(
  roomId: string,
  dayId: string,
  day: DocumentData,
): Promise<void> {
  const dayRef = roomDayRef(roomId, dayId);
  const answersSnap = await dayRef.collection("answers").get();
  const questions = (Array.isArray(day.questions) ? day.questions : []) as RoomDayQuestion[];
  const activeQids = questions
    .filter((question) => question.pulled !== true)
    .map((question) => question.qid);

  const picksByUid = new Map<string, RoomPick[]>();
  answersSnap.docs.forEach((doc) => {
    const picks = (Array.isArray(doc.data().picks) ? doc.data().picks : []) as RoomPick[];
    picksByUid.set(doc.id, picks.filter((pick) => activeQids.includes(pick.qid)));
  });

  const sideCounts = new Map<string, { a: number; b: number }>();
  activeQids.forEach((qid) => sideCounts.set(qid, { a: 0, b: 0 }));
  for (const picks of picksByUid.values()) {
    for (const pick of picks) {
      const counts = sideCounts.get(pick.qid);
      if (!counts) continue;
      if (pick.side === "a") counts.a += 1;
      else counts.b += 1;
    }
  }

  // All members, not just answerers — ranks below cover the whole room.
  const allMemberSnaps = await roomRef(roomId).collection("members").get();
  const allMemberDataByUid = new Map<string, DocumentData>();
  allMemberSnaps.docs.forEach((snap) => {
    allMemberDataByUid.set(snap.id, snap.data() ?? {});
  });
  const memberDataByUid = new Map<string, DocumentData>();
  for (const uid of picksByUid.keys()) {
    const data = allMemberDataByUid.get(uid);
    if (data) memberDataByUid.set(uid, data);
  }

  const results: RoomMemberDayResult[] = [];
  const accuracyByUid = new Map<string, Map<string, number>>();
  for (const [uid, picks] of picksByUid.entries()) {
    const accuracies: number[] = [];
    const perQuestion = new Map<string, number>();
    for (const pick of picks) {
      if (pick.prediction == null) continue;
      const counts = sideCounts.get(pick.qid);
      if (!counts) continue;
      const total = counts.a + counts.b;
      const others = total - 1;
      if (others <= 0) continue;
      const sameSide = (pick.side === "a" ? counts.a : counts.b) - 1;
      const actualShare = Math.round((sameSide / others) * 100);
      const accuracy = calculateReadAccuracy(pick.prediction, actualShare);
      accuracies.push(accuracy);
      perQuestion.set(pick.qid, accuracy);
    }
    accuracyByUid.set(uid, perQuestion);
    results.push({
      uid,
      accuracies,
      questionsAnswered: Number(memberDataByUid.get(uid)?.questionsAnswered ?? 0),
    });
  }

  const deltas = roomDailyScoreDeltas(results);
  const deltaByUid = new Map(deltas.map((delta) => [delta.uid, delta]));

  const writes: Array<(batch: WriteBatch) => void> = [];
  for (const [uid] of picksByUid.entries()) {
    const delta = deltaByUid.get(uid);
    const memberDocRef = roomRef(roomId).collection("members").doc(uid);
    if (delta && memberDataByUid.has(uid)) {
      // Skip members who left between lock and close — a merge write here
      // would resurrect a ghost member doc.
      writes.push((batch) => batch.set(memberDocRef, {
        roomScore: FieldValue.increment(delta.delta),
        lastDelta: delta.delta,
        lastScoredDailyKey: dayId,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true }));
    }
    const perQuestion = accuracyByUid.get(uid) ?? new Map();
    writes.push((batch) => batch.set(dayRef.collection("answers").doc(uid), {
      scored: !!delta,
      scoreDelta: delta?.delta ?? 0,
      avgAccuracy: delta?.avgAccuracy ?? null,
      accuracies: Object.fromEntries(perQuestion),
      scoredAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  }

  // Standings across the whole room by post-delta score (prototype room
  // cards show "Rank #N"). Ties share the higher rank via score ordering.
  const standings = [...allMemberDataByUid.entries()]
    .map(([uid, data]) => ({
      uid,
      score: Number(data.roomScore ?? 0) + (deltaByUid.get(uid)?.delta ?? 0),
    }))
    .sort((a, b) => b.score - a.score);
  standings.forEach((standing, index) => {
    const memberDocRef = roomRef(roomId).collection("members").doc(standing.uid);
    writes.push((batch) => batch.set(memberDocRef, {
      rank: index + 1,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
  });

  const questionResults = activeQids.map((qid) => {
    const counts = sideCounts.get(qid) ?? { a: 0, b: 0 };
    const total = counts.a + counts.b;
    return {
      qid,
      answers: total,
      aCount: counts.a,
      bCount: counts.b,
      aPct: total > 0 ? Math.round((counts.a / total) * 100) : 0,
    };
  });
  writes.push((batch) => batch.set(dayRef, {
    status: "closed",
    results: questionResults,
    scoredMembers: deltas.length,
    closedAt: FieldValue.serverTimestamp(),
  }, { merge: true }));
  writes.push((batch) => batch.set(roomRef(roomId), {
    lastClosedDailyKey: dayId,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true }));
  await commitBatchedWrites(writes);
}

/** Total registered users — the gate for The World's global scoring. */
async function countTotalUsers(): Promise<number> {
  return countQuery(db.collection("users"));
}

/**
 * The World scores predictions automatically once the app is big enough. The
 * admin flag is a manual override so it can be exercised before then [Mike].
 */
async function worldScoringUnlocked(): Promise<boolean> {
  if (await appFeatureEnabled("feature_world_room_unlocked")) return true;
  return (await countTotalUsers()) >= WORLD_PLAYER_GOAL;
}

/**
 * Reveal + score a single World question once it crosses its answer threshold.
 * Unlike rooms (which close on the daily rollover), World questions accumulate
 * answers across days and reveal per question. Idempotent: the first caller
 * claims the qid; later callers no-op.
 */
async function revealWorldQuestion(dailyKey: string, qid: string): Promise<boolean> {
  const dayRef = roomDayRef(WORLD_ROOM_ID, dailyKey);

  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(dayRef);
    if (!snap.exists) return false;
    const revealed = new Set(
      (Array.isArray(snap.data()?.revealedQids) ? snap.data()?.revealedQids : []) as string[],
    );
    if (revealed.has(qid)) return false;
    tx.update(dayRef, { revealedQids: FieldValue.arrayUnion(qid) });
    return true;
  });
  if (!claimed) return false;

  const answersSnap = await dayRef.collection("answers").get();
  let aCount = 0;
  let bCount = 0;
  const rawPredictors: Array<{ uid: string; side: "a" | "b"; prediction: number }> = [];
  for (const doc of answersSnap.docs) {
    const picks = Array.isArray(doc.data().picks) ? doc.data().picks : [];
    const pick = (picks as Array<Record<string, unknown>>).find((p) => p?.qid === qid);
    if (!pick) continue;
    const side = pick.side === "a" || pick.side === "b" ? pick.side : null;
    if (!side) continue;
    if (side === "a") aCount += 1;
    else bCount += 1;
    if (typeof pick.prediction === "number") {
      rawPredictors.push({ uid: doc.id, side, prediction: pick.prediction });
    }
  }

  // Fetch each predictor's lifetime world-scored count for the K-factor.
  const predictorUids = rawPredictors.map((entry) => entry.uid);
  const worldScoredByUid = new Map<string, number>();
  for (const chunk of chunkArray(predictorUids, 300)) {
    if (chunk.length === 0) continue;
    const refs = chunk.map((uid) => db.collection("users").doc(uid));
    const snaps = await db.getAll(...refs);
    snaps.forEach((snap) => {
      worldScoredByUid.set(snap.id, Number(snap.data()?.worldQuestionsScored ?? 0));
    });
  }

  const predictors: WorldPredictorInput[] = rawPredictors.map((entry) => ({
    uid: entry.uid,
    side: entry.side,
    prediction: entry.prediction,
    worldQuestionsScored: worldScoredByUid.get(entry.uid) ?? 0,
  }));
  const { aPct, scores } = scoreWorldQuestion({ aCount, bCount, predictors });
  const deltaByUid = new Map(scores.map((score) => [score.uid, score]));

  const writes: Array<(batch: WriteBatch) => void> = [];
  for (const predictor of predictors) {
    const score = deltaByUid.get(predictor.uid);
    if (!score) continue;
    writes.push((batch) => batch.set(db.collection("users").doc(predictor.uid), {
      worldReadScore: FieldValue.increment(score.delta),
      worldQuestionsScored: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true }));
    writes.push((batch) => batch.set(dayRef.collection("answers").doc(predictor.uid), {
      [`worldAccuracies.${qid}`]: score.accuracy,
      [`worldScoreDeltas.${qid}`]: score.delta,
      scoredQids: FieldValue.arrayUnion(qid),
    }, { merge: true }));
  }

  const answers = aCount + bCount;
  writes.push((batch) => batch.set(dayRef, {
    results: FieldValue.arrayUnion({ qid, answers, aCount, bCount, aPct }),
    [`revealedAt.${qid}`]: FieldValue.serverTimestamp(),
  }, { merge: true }));
  await commitBatchedWrites(writes);

  // Mark the day closed once every one of its questions has revealed.
  const daySnap = await dayRef.get();
  const day = daySnap.data() ?? {};
  const activeQids = ((day.questions ?? []) as RoomDayQuestion[])
    .filter((question) => question.pulled !== true)
    .map((question) => question.qid);
  const revealedQids = new Set(
    (Array.isArray(day.revealedQids) ? day.revealedQids : []) as string[],
  );
  if (activeQids.length > 0 && activeQids.every((id) => revealedQids.has(id))) {
    await dayRef.set({ status: "closed", closedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  logger.info("World question revealed", { dailyKey, qid, answers, scored: scores.length });
  return true;
}

export const rolloverRooms = onSchedule({
  schedule: "0 0 * * *",
  timeZone: EASTERN_TIME_ZONE,
}, async () => {
  const todayKey = dailyKeyForEasternDate(new Date());
  await ensureWorldRoom();
  const roomsSnap = await db.collection("rooms").get();
  let closed = 0;
  let assigned = 0;
  for (const roomDoc of roomsSnap.docs) {
    try {
      const rolloverPlan = roomRolloverPlan(roomDoc.id);
      // The World keeps its threshold-based reveal behavior, but still needs a
      // fresh set every day. A curated day is activated when present;
      // otherwise assembleRoomDay deterministically selects three bank
      // questions for the date.
      if (!rolloverPlan.closePreviousDays) {
        if (rolloverPlan.ensureToday &&
          await assembleRoomDay(roomDoc.id, roomDoc.data(), todayKey)) {
          assigned += 1;
        }
        continue;
      }
      const liveDays = await roomDoc.ref.collection("days")
        .where("status", "==", "live")
        .get();
      for (const dayDoc of liveDays.docs) {
        if (dayDoc.id >= todayKey) continue;
        await closeRoomDay(roomDoc.id, dayDoc.id, dayDoc.data());
        closed += 1;
      }
      if (rolloverPlan.ensureToday &&
        await assembleRoomDay(roomDoc.id, roomDoc.data(), todayKey)) {
        assigned += 1;
      }
    } catch (error) {
      logger.error("Room rollover failed", { roomId: roomDoc.id, error: String(error) });
    }
  }
  logger.info("Room rollover complete", { todayKey, rooms: roomsSnap.size, closed, assigned });
});

export const createRoom = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  let name: string;
  let tier: BankTier;
  let color: string;
  let cats: string[];
  try {
    name = normalizeRoomName(request.data?.name);
    tier = normalizeRoomTier(request.data?.tier ?? "normal");
    color = normalizeRoomColor(request.data?.color);
    cats = normalizeRoomCats(request.data?.cats);
  } catch (error) {
    mapRoomValidationError(error);
  }
  const customEnabled = request.data?.customEnabled !== false;
  const revealAnswersDefault = request.data?.revealAnswers !== false;

  const newRoomRef = db.collection("rooms").doc();
  const { code } = await createShortLink({
    type: "room",
    targetId: newRoomRef.id,
    createdBy: uid,
  });
  const displayName = await displayNameForUid(uid);
  const batch = db.batch();
  batch.set(newRoomRef, {
    name,
    color,
    tier,
    cats,
    customEnabled,
    revealAnswersDefault,
    createdBy: uid,
    isWorld: false,
    memberCount: 1,
    usedQuestionIds: [],
    inviteCode: code,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(newRoomRef.collection("members").doc(uid), {
    role: "creator",
    displayName,
    revealMine: revealAnswersDefault,
    roomScore: ROOM_STARTING_SCORE,
    streak: 0,
    questionsAnswered: 0,
    joinedAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.collection("users").doc(uid).collection("memberships").doc(newRoomRef.id), {
    roomId: newRoomRef.id,
    joinedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  await applyUserDislikesToRoom(uid, newRoomRef.id, 1);

  const todayKey = dailyKeyForEasternDate(new Date());
  await assembleRoomDay(newRoomRef.id, {
    name, color, tier, cats, customEnabled, isWorld: false, usedQuestionIds: [],
  }, todayKey);
  return { roomId: newRoomRef.id, inviteCode: code, name };
});

export const joinRoom = onCall(emailCallableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const code = assertString(request.data?.code, "code").toUpperCase();
  const linkSnap = await db.collection("links").doc(code).get();
  const link = linkSnap.data();
  if (!linkSnap.exists || link?.type !== "room") {
    throw new HttpsError("not-found", "That room code is not valid.");
  }
  if (shortLinkExpired(timestampDate(link?.expiresAt))) {
    throw new HttpsError("failed-precondition", "That room code has expired.");
  }
  const roomId = String(link?.targetId ?? "");
  const targetRoomRef = roomRef(roomId);

  if (request.data?.previewOnly === true) {
    // Pre-join preview so the client can show the room card and run the
    // After Dark consent before actually joining (prototype join sheet).
    const roomSnap = await targetRoomRef.get();
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data() ?? {};
    const memberSnap = await targetRoomRef.collection("members").doc(uid).get();
    return {
      preview: true,
      roomId,
      name: String(room.name ?? "Room"),
      color: String(room.color ?? ""),
      tier: String(room.tier ?? "normal"),
      memberCount: Number(room.memberCount ?? 0),
      alreadyMember: memberSnap.exists,
    };
  }

  const displayName = await displayNameForUid(uid);
  let joinedNewMember = false;
  let roomName = "Room";
  const tier = await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(targetRoomRef);
    if (!roomSnap.exists) {
      throw new HttpsError("not-found", "Room not found.");
    }
    roomName = String(roomSnap.data()?.name ?? "Room");
    const memberRef = targetRoomRef.collection("members").doc(uid);
    const memberSnap = await tx.get(memberRef);
    if (memberSnap.exists) {
      return String(roomSnap.data()?.tier ?? "normal");
    }
    joinedNewMember = true;
    tx.set(memberRef, {
      role: "member",
      displayName,
      revealMine: roomSnap.data()?.revealAnswersDefault !== false,
      roomScore: ROOM_STARTING_SCORE,
      streak: 0,
      questionsAnswered: 0,
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.collection("users").doc(uid).collection("memberships").doc(roomId), {
      roomId,
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.set(targetRoomRef, {
      memberCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return String(roomSnap.data()?.tier ?? "normal");
  });
  if (joinedNewMember) {
    await applyUserDislikesToRoom(uid, roomId, 1);
    try {
      const creatorSnap = await targetRoomRef.collection("members")
        .where("role", "==", "creator")
        .limit(1)
        .get();
      const creatorUid = creatorSnap.docs[0]?.id ?? "";
      await notifyMembersOfJoin({
        roomId,
        creatorUid,
        joinedUid: uid,
        joinedName: displayName,
        roomName,
      });
    } catch (error) {
      logger.warn("Room join notification failed", { roomId, uid, error: String(error) });
    }
  }
  return { joined: true, roomId, tier };
});

export const leaveRoom = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const { room, member } = await requireRoomAndMember(roomId, uid);
  if (room.isWorld === true) {
    throw new HttpsError("failed-precondition", "The World room cannot be left.");
  }

  const membersSnap = await roomRef(roomId).collection("members").get();
  const others = membersSnap.docs.filter((doc) => doc.id !== uid);
  const batch = db.batch();
  batch.delete(roomRef(roomId).collection("members").doc(uid));
  batch.delete(db.collection("users").doc(uid).collection("memberships").doc(roomId));

  if (others.length === 0) {
    batch.delete(roomRef(roomId));
    await batch.commit();
    await db.recursiveDelete(roomRef(roomId));
    return { left: true, roomDeleted: true };
  }

  if (member.role === "creator") {
    // Transfer creator to the longest-standing remaining member.
    const successor = [...others].sort((a, b) => {
      const aJoined = timestampDate(a.data().joinedAt)?.getTime() ?? 0;
      const bJoined = timestampDate(b.data().joinedAt)?.getTime() ?? 0;
      return aJoined - bJoined;
    })[0];
    batch.set(successor.ref, { role: "creator" }, { merge: true });
  }
  batch.set(roomRef(roomId), {
    memberCount: FieldValue.increment(-1),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
  await applyUserDislikesToRoom(uid, roomId, -1);
  return { left: true, roomDeleted: false };
});

export const deleteRoom = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const room = await requireRoomCreator(roomId, uid);
  if (room.isWorld === true) {
    throw new HttpsError("failed-precondition", "The World room cannot be deleted.");
  }
  const membersSnap = await roomRef(roomId).collection("members").get();
  const batch = db.batch();
  membersSnap.docs.forEach((doc) => {
    batch.delete(db.collection("users").doc(doc.id).collection("memberships").doc(roomId));
  });
  if (typeof room.inviteCode === "string" && room.inviteCode.length > 0) {
    batch.delete(db.collection("links").doc(room.inviteCode));
  }
  await batch.commit();
  await db.recursiveDelete(roomRef(roomId));
  return { deleted: true, roomId };
});

export const updateRoomSettings = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const room = await requireRoomCreator(roomId, uid);
  if (room.isWorld === true) {
    throw new HttpsError("failed-precondition", "The World room is managed by the game.");
  }
  const updates: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
  try {
    if (request.data?.name != null) updates.name = normalizeRoomName(request.data.name);
    if (request.data?.tier != null) updates.tier = normalizeRoomTier(request.data.tier);
    if (request.data?.color != null) updates.color = normalizeRoomColor(request.data.color);
    if (request.data?.cats != null) updates.cats = normalizeRoomCats(request.data.cats);
    if (request.data?.customEnabled != null) updates.customEnabled = request.data.customEnabled === true;
  } catch (error) {
    mapRoomValidationError(error);
  }
  await roomRef(roomId).set(updates, { merge: true });
  return { updated: true, roomId };
});

export const setRoomQuestionEnabled = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const qid = assertString(request.data?.qid, "qid");
  const enabled = request.data?.enabled === true;
  await requireRoomCreator(roomId, uid);
  const todayKey = dailyKeyForEasternDate(new Date());
  const dayRef = roomDayRef(roomId, todayKey);
  await db.runTransaction(async (tx) => {
    const daySnap = await tx.get(dayRef);
    if (!daySnap.exists || daySnap.data()?.status !== "live") {
      throw new HttpsError("failed-precondition", "No live question set for today.");
    }
    const questions = (daySnap.data()?.questions ?? []) as RoomDayQuestion[];
    const next = questions.map((question) =>
      question.qid === qid ? { ...question, pulled: !enabled } : question);
    if (!questions.some((question) => question.qid === qid)) {
      throw new HttpsError("not-found", "That question is not in today's set.");
    }
    tx.set(dayRef, { questions: next }, { merge: true });
  });
  return { qid, enabled };
});

export const setRoomAnswerVisibility = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const revealMine = request.data?.revealMine === true;
  await requireRoomAndMember(roomId, uid);
  await roomRef(roomId).collection("members").doc(uid).set({
    revealMine,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { roomId, revealMine };
});

export const markRoomRevealSeen = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const { room } = await requireRoomAndMember(roomId, uid);
  const lastClosed = typeof room.lastClosedDailyKey === "string" ? room.lastClosedDailyKey : null;
  await roomRef(roomId).collection("members").doc(uid).set({
    revealSeenDailyKey: lastClosed,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { roomId, revealSeenDailyKey: lastClosed };
});

export const lockRoomAnswers = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const todayKey = dailyKeyForEasternDate(new Date());

  const roomSnap = await roomRef(roomId).get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
  const room = roomSnap.data() ?? {};
  const isWorld = room.isWorld === true;

  const memberDocRef = roomRef(roomId).collection("members").doc(uid);
  let memberSnap = await memberDocRef.get();
  if (!memberSnap.exists && isWorld) {
    // The World auto-enrolls on first answer.
    const enrollDisplayName = await displayNameForUid(uid);
    await db.runTransaction(async (tx) => {
      // All reads first (Firestore requires reads before writes).
      const fresh = await tx.get(memberDocRef);
      if (fresh.exists) return;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await tx.get(userRef);

      tx.set(memberDocRef, {
        role: "member",
        displayName: enrollDisplayName,
        revealMine: false,
        roomScore: ROOM_STARTING_SCORE,
        streak: 0,
        questionsAnswered: 0,
        joinedAt: FieldValue.serverTimestamp(),
      });
      tx.set(userRef.collection("memberships").doc(roomId), {
        roomId,
        joinedAt: FieldValue.serverTimestamp(),
      });
      // Seed the reader's World Read Score so later reveal deltas move a real
      // 1500 baseline rather than starting from zero.
      if (typeof userSnap.data()?.worldReadScore !== "number") {
        tx.set(userRef, {
          worldReadScore: ROOM_STARTING_SCORE,
          worldQuestionsScored: Number(userSnap.data()?.worldQuestionsScored ?? 0),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      tx.set(roomRef(roomId), {
        memberCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    memberSnap = await memberDocRef.get();
  }
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "You are not a member of this room.");
  }
  const member = memberSnap.data() ?? {};

  // The World lets readers answer past, not-yet-revealed days too (instant
  // lock, no 24h gap); everyone else answers only today's live set.
  const requestedDailyKey = isWorld
    ? (normalizeDailyKey(request.data?.dailyKey) ?? todayKey)
    : todayKey;
  if (requestedDailyKey > todayKey) {
    throw new HttpsError("failed-precondition", "That day is not open yet.");
  }
  const dailyKey = requestedDailyKey;
  const isToday = dailyKey === todayKey;

  const dayRef = roomDayRef(roomId, dailyKey);
  const daySnap = await dayRef.get();
  if (!daySnap.exists || daySnap.data()?.status !== "live") {
    throw new HttpsError("failed-precondition", "Those questions are not open.");
  }
  const day = daySnap.data() ?? {};
  // World questions that already revealed are locked out; readers can only
  // answer the ones still accumulating.
  const revealedQids = new Set(
    (Array.isArray(day.revealedQids) ? day.revealedQids : []) as string[],
  );
  const activeQuestions = ((day.questions ?? []) as RoomDayQuestion[])
    .filter((question) => question.pulled !== true && !revealedQids.has(question.qid));
  const activeQids = new Set(activeQuestions.map((question) => question.qid));
  if (activeQids.size === 0) {
    throw new HttpsError("failed-precondition", "These questions have already revealed.");
  }

  // Predictions are always captured now (solo and World included): the reader
  // guesses what share of people would agree. Solo/early answers simply go
  // unscored until there are other responses to compare against [Mike].
  const answerOnly = false;

  const rawPicks = Array.isArray(request.data?.picks) ? request.data.picks : [];
  let picks: RoomPick[];
  try {
    picks = rawPicks.map((raw: Record<string, unknown>) => {
      const qid = assertString(raw?.qid, "picks.qid");
      const side = raw?.side === "a" || raw?.side === "b" ? raw.side : null;
      if (!side) throw new HttpsError("invalid-argument", "picks.side must be 'a' or 'b'.");
      if (!activeQids.has(qid)) {
        throw new HttpsError("invalid-argument", `Question ${qid} is not in today's set.`);
      }
      return {
        qid,
        side,
        prediction: answerOnly
          ? null
          : normalizePrediction(raw?.prediction ?? raw?.predictedShare),
      };
    });
  } catch (error) {
    mapRoomValidationError(error);
  }
  if (picks.length !== activeQids.size ||
      new Set(picks.map((pick) => pick.qid)).size !== picks.length) {
    throw new HttpsError("invalid-argument", "Answers must cover each open question exactly once.");
  }
  if (!answerOnly && picks.some((pick) => pick.prediction == null)) {
    throw new HttpsError("invalid-argument", "Each answer needs a prediction in this room.");
  }

  const predictedCount = picks.filter((pick) => pick.prediction != null).length;
  const streak = nextStreakForDailyKey(
    typeof member.lastPlayedDailyKey === "string" ? member.lastPlayedDailyKey : null,
    todayKey,
    Number(member.streak ?? 0),
  );

  const answerDocRef = dayRef.collection("answers").doc(uid);
  let createdAnswer = false;
  await db.runTransaction(async (tx) => {
    const answerSnap = await tx.get(answerDocRef);
    const existing = answerSnap.exists ? answerSnap.data() ?? {} : null;
    createdAnswer = existing == null;
    const existingPicks = Array.isArray(existing?.picks)
      ? (existing.picks as Array<Record<string, unknown>>)
        .map((raw) => ({
          qid: typeof raw.qid === "string" ? raw.qid : "",
          prediction: typeof raw.prediction === "number"
            ? raw.prediction
            : typeof raw.predictedShare === "number"
              ? raw.predictedShare
              : null,
        }))
        .filter((pick) => pick.qid.length > 0)
      : [];
    const existingQids = new Set(existingPicks.map((pick) => pick.qid));
    const nextQids = new Set(picks.map((pick) => pick.qid));
    const existingPredictedCount = existingPicks
      .filter((pick) => pick.prediction != null).length;
    const predictedDelta = predictedCount - existingPredictedCount;

    const counterUpdates: Record<string, unknown> = {};
    if (createdAnswer) {
      counterUpdates.answerCount = FieldValue.increment(1);
    }
    picks.forEach((pick) => {
      if (!existingQids.has(pick.qid)) {
        counterUpdates[`answerCounts.${pick.qid}`] = FieldValue.increment(1);
      }
    });
    existingQids.forEach((qid) => {
      if (!nextQids.has(qid)) {
        counterUpdates[`answerCounts.${qid}`] = FieldValue.increment(-1);
      }
    });
    if (Object.keys(counterUpdates).length > 0) {
      tx.update(dayRef, counterUpdates);
    }

    if (createdAnswer) {
      tx.set(answerDocRef, {
        picks,
        answerOnly,
        lockedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        scored: false,
      });
    } else {
      tx.set(answerDocRef, {
        picks,
        answerOnly,
        updatedAt: FieldValue.serverTimestamp(),
        scored: false,
      }, { merge: true });
    }

    const memberUpdates: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
    };
    // Streak only advances for today's set; answering an older World day
    // (catch-up) must not bump the streak or the day counter.
    if (isToday) {
      memberUpdates.streak = streak;
      memberUpdates.lastPlayedDailyKey = todayKey;
    }
    // The World tracks its own worldQuestionsScored (bumped at reveal); only
    // room predictions feed the room/global answered counters.
    if (!isWorld && predictedDelta !== 0) {
      memberUpdates.questionsAnswered = FieldValue.increment(predictedDelta);
    }
    tx.set(memberDocRef, memberUpdates, { merge: true });
    if (!isWorld && predictedDelta !== 0) {
      tx.set(db.collection("users").doc(uid), {
        officialQuestionsAnswered: FieldValue.increment(predictedDelta),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });

  // The World reveals + scores each question the moment it crosses its answer
  // threshold and the app is big enough (5K users, or the admin override).
  if (isWorld) {
    try {
      const freshDay = (await dayRef.get()).data() ?? {};
      const counts = (freshDay.answerCounts ?? {}) as Record<string, number>;
      const questionsById = new Map(
        ((freshDay.questions ?? []) as RoomDayQuestion[]).map((question) => [question.qid, question]),
      );
      const crossed = picks.filter((pick) => {
        const question = questionsById.get(pick.qid) as { threshold?: number } | undefined;
        const threshold = Number(question?.threshold ?? 1000);
        return Number(counts[pick.qid] ?? 0) >= threshold;
      });
      if (crossed.length > 0 && (await worldScoringUnlocked())) {
        for (const pick of crossed) {
          await revealWorldQuestion(dailyKey, pick.qid);
        }
      }
    } catch (error) {
      logger.warn("World reveal check failed", { dailyKey, error: String(error) });
    }
  }

  return {
    locked: createdAnswer,
    updated: !createdAnswer,
    roomId,
    dailyKey,
    answerOnly,
    streak: isToday ? streak : Number(member.streak ?? 0),
  };
});

/**
 * The World leaderboard: how you read all of humanity versus everyone you
 * share a (non-World) room with. Ranked by the dedicated World Read Score,
 * which only moves as World questions cross their thresholds and score [Mike].
 */
export const getWorldLeaderboard = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const membershipsSnap = await db.collection("users").doc(uid)
    .collection("memberships").get();
  const roomIds = membershipsSnap.docs
    .map((doc) => String(doc.data()?.roomId ?? doc.id))
    .filter((id) => id.length > 0 && id !== WORLD_ROOM_ID);

  const peerUids = new Set<string>([uid]);
  for (const roomId of roomIds) {
    if (peerUids.size >= WORLD_LEADERBOARD_PEER_CAP) break;
    const membersSnap = await roomRef(roomId).collection("members").get();
    membersSnap.docs.forEach((doc) => peerUids.add(doc.id));
  }

  const uids = [...peerUids].slice(0, WORLD_LEADERBOARD_PEER_CAP);
  const rowsInput: LeaderboardInput[] = [];
  for (const chunk of chunkArray(uids, 300)) {
    if (chunk.length === 0) continue;
    const snaps = await db.getAll(...chunk.map((id) => db.collection("users").doc(id)));
    snaps.forEach((snap) => {
      const data = snap.data() ?? {};
      rowsInput.push({
        uid: snap.id,
        displayName: typeof data.displayName === "string" ? data.displayName : "Reader",
        avatarColor: typeof data.avatarColor === "string" ? data.avatarColor : "blue",
        readScore: Number(data.worldReadScore ?? STARTING_READ_SCORE),
        officialQuestionsAnswered: Number(data.worldQuestionsScored ?? 0),
        currentStreak: Number(data.currentStreak ?? 0),
      });
    });
  }

  const rows = rankedLeaderboardRows(rowsInput, WORLD_LEADERBOARD_PEER_CAP);
  const me = rows.find((row) => row.uid === uid) ?? null;
  return { rows, me, total: rows.length };
});

export const queueCustomQuestion = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const { room, member } = await requireRoomAndMember(roomId, uid);
  if (room.isWorld === true || room.customEnabled === false) {
    throw new HttpsError("failed-precondition", "Custom questions are off in this room.");
  }
  if (member.customQuestionsBlocked === true) {
    throw new HttpsError(
      "permission-denied",
      "The room creator has blocked this account from submitting custom questions.",
    );
  }
  if (request.data?.acceptedCommunityStandards !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Agree to the custom-question rules before submitting.",
    );
  }
  let text: string;
  let optA: string;
  let optB: string;
  try {
    text = normalizeCustomQuestionText(request.data?.text);
    optA = normalizeCustomOption(request.data?.optA, "Yes");
    optB = normalizeCustomOption(request.data?.optB, "No");
    if (hasClearlyObjectionableContent(`${text} ${optA} ${optB}`)) {
      throw new RoomValidationError(
        "This question may violate our community standards. Please revise it.",
      );
    }
  } catch (error) {
    mapRoomValidationError(error);
  }
  const queueRef = roomRef(roomId).collection("queue");
  const mineSnap = await queueRef.where("authorUid", "==", uid).get();
  if (mineSnap.size >= CUSTOM_QUEUE_CAP_PER_MEMBER) {
    throw new HttpsError("resource-exhausted",
      `You can queue up to ${CUSTOM_QUEUE_CAP_PER_MEMBER} questions per room.`);
  }
  const displayName = await displayNameForUid(uid);
  await db.collection("users").doc(uid).set({
    customQuestionTermsVersion: CUSTOM_QUESTION_TERMS_VERSION,
    customQuestionTermsAcceptedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  const itemRef = await queueRef.add({
    text,
    optA,
    optB,
    authorUid: uid,
    authorName: displayName,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { queued: true, itemId: itemRef.id, remaining: CUSTOM_QUEUE_CAP_PER_MEMBER - mineSnap.size - 1 };
});

export const deleteCustomQuestion = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const itemId = assertString(request.data?.itemId, "itemId");
  const { member } = await requireRoomAndMember(roomId, uid);
  const itemRef = roomRef(roomId).collection("queue").doc(itemId);
  const itemSnap = await itemRef.get();
  if (!itemSnap.exists) return { deleted: false };
  if (itemSnap.data()?.authorUid !== uid && member.role !== "creator") {
    throw new HttpsError("permission-denied", "Only the author or room creator can remove this.");
  }
  await itemRef.delete();
  return { deleted: true };
});

export const flagRoomQuestion = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const qid = assertString(request.data?.qid, "qid");
  const { room, member } = await requireRoomAndMember(roomId, uid);
  const allowedReasons = new Set(["abuse", "hate", "sexual", "threat", "spam", "other"]);
  const reason = typeof request.data?.reason === "string"
    ? request.data.reason.trim().toLowerCase()
    : "other";
  if (!allowedReasons.has(reason)) {
    throw new HttpsError("invalid-argument", "Choose a valid report reason.");
  }
  const blockAuthor = request.data?.blockAuthor === true;
  if (blockAuthor && member.role !== "creator") {
    throw new HttpsError(
      "permission-denied",
      "Only the room creator can block a member from submitting questions.",
    );
  }
  const todayKey = dailyKeyForEasternDate(new Date());
  const dayRef = roomDayRef(roomId, todayKey);

  const flagged = await db.runTransaction(async (tx) => {
    const daySnap = await tx.get(dayRef);
    if (!daySnap.exists || daySnap.data()?.status !== "live") {
      throw new HttpsError("failed-precondition", "Flags apply to today's live questions.");
    }
    const questions = (daySnap.data()?.questions ?? []) as RoomDayQuestion[];
    const target = questions.find((question) => question.qid === qid);
    if (!target) throw new HttpsError("not-found", "That question is not in today's set.");
    if (target.custom !== true) {
      throw new HttpsError("failed-precondition", "Only custom questions can be flagged.");
    }
    if (target.pulled === true) return target;
    tx.set(dayRef, {
      questions: questions.map((question) =>
        question.qid === qid ? { ...question, pulled: true } : question),
    }, { merge: true });
    return target;
  });

  await db.collection("flags").add({
    roomId,
    roomName: String(room.name ?? ""),
    dailyKey: todayKey,
    qid,
    prompt: flagged.prompt,
    authorUid: flagged.authorUid,
    authorName: flagged.authorName,
    flaggedBy: uid,
    reason,
    status: "open",
    reviewDueAt: Timestamp.fromMillis(Date.now() + CONTENT_REPORT_RESPONSE_MS),
    authorBlockedFromRoom: blockAuthor,
    createdAt: FieldValue.serverTimestamp(),
  });

  if (blockAuthor && flagged.authorUid && flagged.authorUid !== uid) {
    const authorUid = flagged.authorUid;
    await roomRef(roomId).collection("members").doc(authorUid).set({
      customQuestionsBlocked: true,
      customQuestionsBlockedAt: FieldValue.serverTimestamp(),
      customQuestionsBlockedBy: uid,
    }, { merge: true });
    await roomRef(roomId).collection("blockedQuestionAuthors").doc(authorUid).set({
      authorUid,
      blockedBy: uid,
      sourceQid: qid,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    const queuedByAuthor = await roomRef(roomId).collection("queue")
      .where("authorUid", "==", authorUid)
      .get();
    await commitBatchedWrites(
      queuedByAuthor.docs.map((doc) => (batch) => batch.delete(doc.ref)),
    );
  }

  // "The author is notified" — best-effort push, never blocks the pull.
  try {
    if (flagged.authorUid && flagged.authorUid !== uid) {
      const tokensSnap = await db.collection("users").doc(flagged.authorUid)
        .collection("notificationTokens")
        .where("enabled", "==", true)
        .get();
      const tokens = tokensSnap.docs
        .map((doc) => ({
          uid: flagged.authorUid ?? "",
          refPath: doc.ref.path,
          token: String(doc.data().token ?? ""),
        }))
        .filter((token) => token.token.length > 0);
      if (tokens.length > 0) {
        await sendNotificationToTokens(tokens, {
          title: "A question was removed",
          body: `Your question in ${String(room.name ?? "a room")} was flagged and pulled for today.`,
          route: "/rooms",
          type: "custom_question_flagged",
        });
      }
    }
  } catch (error) {
    logger.warn("Flag notification failed", { roomId, qid, error: String(error) });
  }
  return { flagged: true, qid, authorBlockedFromRoom: blockAuthor };
});

export const resolveContentFlag = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const flagId = assertString(request.data?.flagId, "flagId");
  const action = request.data?.action === "disable-author" ? "disable-author" : "dismiss";
  const flagRef = db.collection("flags").doc(flagId);
  const flagSnap = await flagRef.get();
  if (!flagSnap.exists) throw new HttpsError("not-found", "Report not found.");
  const flag = flagSnap.data() ?? {};

  if (action === "disable-author") {
    const authorUid = typeof flag.authorUid === "string" ? flag.authorUid : "";
    if (!authorUid) {
      throw new HttpsError("failed-precondition", "This report has no author account.");
    }
    await getAuth().updateUser(authorUid, { disabled: true });
  }

  await flagRef.set({
    status: "resolved",
    resolution: action,
    resolvedAt: FieldValue.serverTimestamp(),
    resolvedBy: uid,
  }, { merge: true });
  return { resolved: true, flagId, action };
});

export const getRoomDayDetail = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const roomId = assertRoomId(request.data?.roomId);
  const dailyKey = normalizeDailyKey(request.data?.dailyKey);
  if (!dailyKey) throw new HttpsError("invalid-argument", "dailyKey is required.");
  await requireRoomAndMember(roomId, uid);

  const dayRef = roomDayRef(roomId, dailyKey);
  const daySnap = await dayRef.get();
  if (!daySnap.exists || daySnap.data()?.status !== "closed") {
    throw new HttpsError("failed-precondition", "Results are available after the reveal.");
  }
  const [answersSnap, membersSnap] = await Promise.all([
    dayRef.collection("answers").get(),
    roomRef(roomId).collection("members").get(),
  ]);
  const memberByUid = new Map(membersSnap.docs.map((doc) => [doc.id, doc.data()]));
  const rows = answersSnap.docs.map((doc) => {
    const data = doc.data();
    const member = memberByUid.get(doc.id) ?? {};
    const reveals = member.revealMine === true || doc.id === uid;
    const picks = (Array.isArray(data.picks) ? data.picks : []) as RoomPick[];
    return {
      uid: doc.id,
      displayName: String(member.displayName ?? "Reader"),
      isMe: doc.id === uid,
      scoreDelta: typeof data.scoreDelta === "number" ? data.scoreDelta : null,
      avgAccuracy: typeof data.avgAccuracy === "number" ? data.avgAccuracy : null,
      accuracies: data.accuracies ?? {},
      reveals,
      picks: reveals
        ? picks.map((pick) => ({ qid: pick.qid, side: pick.side, prediction: pick.prediction }))
        : [],
    };
  });
  rows.sort((a, b) => (b.avgAccuracy ?? -1) - (a.avgAccuracy ?? -1));
  return {
    roomId,
    dailyKey,
    questions: daySnap.data()?.questions ?? [],
    results: daySnap.data()?.results ?? [],
    rows,
  };
});

export const setQuestionReaction = onCall(authOnlyCallableOptions, async (request) => {
  const uid = requireUid(request.auth);
  const qid = assertQuestionReactionId(request.data?.qid);
  const rawReaction = request.data?.reaction;
  const nextReaction = rawReaction === null || rawReaction === undefined
    ? null
    : rawReaction === "liked" || rawReaction === "disliked"
      ? rawReaction
      : null;
  if (rawReaction !== null && rawReaction !== undefined && nextReaction === null) {
    throw new HttpsError("invalid-argument", "reaction must be liked, disliked, or null.");
  }

  const userRef = db.collection("users").doc(uid);
  const feedbackRef = db.collection("questionFeedback").doc(qid);
  let memberRoomDislikeDelta = 0;
  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const user = userSnap.data() ?? {};
    const liked = Array.isArray(user.likedQuestionIds)
      ? user.likedQuestionIds.map(String)
      : [];
    const disliked = Array.isArray(user.dislikedQuestionIds)
      ? user.dislikedQuestionIds.map(String)
      : [];
    const previousReaction = liked.includes(qid)
      ? "liked"
      : disliked.includes(qid)
        ? "disliked"
        : null;
    if (previousReaction === nextReaction) return;

    const userUpdates: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (nextReaction === "liked") {
      userUpdates.likedQuestionIds = FieldValue.arrayUnion(qid);
      userUpdates.dislikedQuestionIds = FieldValue.arrayRemove(qid);
    } else if (nextReaction === "disliked") {
      userUpdates.dislikedQuestionIds = FieldValue.arrayUnion(qid);
      userUpdates.likedQuestionIds = FieldValue.arrayRemove(qid);
    } else {
      userUpdates.likedQuestionIds = FieldValue.arrayRemove(qid);
      userUpdates.dislikedQuestionIds = FieldValue.arrayRemove(qid);
    }
    tx.set(userRef, userUpdates, { merge: true });

    const likeDelta =
      (nextReaction === "liked" ? 1 : 0) - (previousReaction === "liked" ? 1 : 0);
    const dislikeDelta =
      (nextReaction === "disliked" ? 1 : 0) -
      (previousReaction === "disliked" ? 1 : 0);
    memberRoomDislikeDelta = dislikeDelta;
    tx.set(feedbackRef, {
      qid,
      likedCount: FieldValue.increment(likeDelta),
      dislikedCount: FieldValue.increment(dislikeDelta),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  await applyQuestionDislikeDeltaToMemberRooms(uid, qid, memberRoomDislikeDelta);

  return { qid, reaction: nextReaction };
});

export const getPartyPool = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAppFeature("feature_party_mode", "Party mode is currently disabled.");
  const requestedCount = Number(request.data?.count ?? 60);
  const count = Math.max(1, Math.min(100, Number.isFinite(requestedCount) ? requestedCount : 60));
  const excludeIds = new Set(
    (Array.isArray(request.data?.excludeIds) ? request.data.excludeIds : [])
      .slice(0, 500)
      .map(String),
  );
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.data() ?? {};
  const allowMature = user.matureContent === true;
  const likedQuestionIds = new Set(
    Array.isArray(user.likedQuestionIds) ? user.likedQuestionIds.map(String) : [],
  );
  const dislikedQuestionIds = new Set(
    Array.isArray(user.dislikedQuestionIds) ? user.dislikedQuestionIds.map(String) : [],
  );

  // Optional spice level: After Dark without recorded consent falls back to
  // Everyday rather than erroring (the client gates the picker on consent).
  const rawTier = typeof request.data?.tier === "string" ? request.data.tier : null;
  const requestedTier = rawTier === null ? null : normalizeRoomTier(rawTier);
  const effectiveTier = requestedTier === "mature" && !allowMature ? "normal" : requestedTier;

  const filterCandidates = (source: CandidateQuestion[]) => source
    .filter((candidate) => allowMature || candidate.tier !== "mature")
    .filter((candidate) => !dislikedQuestionIds.has(candidate.id))
    .filter((candidate) =>
      effectiveTier === null || tierAllowsQuestion(effectiveTier, candidate.tier));
  const bankPool = filterCandidates(await bankCandidates());
  const fallbackPool = bankPool.length > 0
    ? []
    : filterCandidates(fallbackPartyCandidates(effectiveTier));
  const candidates = bankPool.length > 0 ? bankPool : fallbackPool;
  if (bankPool.length === 0) {
    logger.warn("Party pool used fallback questions", {
      uid,
      requestedTier: effectiveTier,
      fallbackCount: fallbackPool.length,
    });
  }
  const fresh = candidates.filter((candidate) => !excludeIds.has(candidate.id));
  const pool = weightedPartyPool(fresh.length >= count ? fresh : candidates, likedQuestionIds);
  return {
    questions: pool.slice(0, count).map((candidate) => ({
      qid: candidate.id,
      prompt: candidate.prompt,
      optA: candidate.optA,
      optB: candidate.optB,
      tag: candidate.tags[0] ?? "Everyday",
      shape: candidate.shape,
      tier: candidate.tier,
    })),
    exhausted: fresh.length < count,
  };
});

export const importQuestionBank = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const rawRows = Array.isArray(request.data?.rows) ? request.data.rows : [];
  if (rawRows.length === 0 || rawRows.length > 500) {
    throw new HttpsError("invalid-argument", "Provide 1-500 rows per import call.");
  }
  let imported = 0;
  const errors: Array<{ index: number; message: string }> = [];
  const writes: Array<(batch: WriteBatch) => void> = [];
  rawRows.forEach((raw: Record<string, unknown>, index: number) => {
    try {
      const question = normalizeBankRow(raw ?? {});
      writes.push((batch) => batch.set(db.collection("questionBank").doc(question.id), {
        prompt: question.prompt,
        optA: question.optA,
        optB: question.optB,
        tags: question.tags,
        tier: question.tier,
        shape: question.shape,
        active: question.active,
        timesUsed: FieldValue.increment(0),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true }));
      imported += 1;
    } catch (error) {
      errors.push({ index, message: error instanceof Error ? error.message : String(error) });
    }
  });
  await commitBatchedWrites(writes);
  return { imported, errors };
});

function normalizeAdminBankTier(value: unknown): BankTier {
  const tier = typeof value === "string" ? value.trim().toLowerCase() : "normal";
  if (tier === "work-safe" || tier === "normal" || tier === "mature") {
    return tier;
  }
  throw new HttpsError("invalid-argument", "tier must be work-safe, normal, or mature.");
}

export const upsertBankQuestion = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const prompt = assertString(request.data?.prompt, "prompt");
  const category = assertString(request.data?.category, "category").toUpperCase();
  const tier = normalizeAdminBankTier(request.data?.tier);
  const active = request.data?.active !== false;
  const explicitQid =
    typeof request.data?.qid === "string" && request.data.qid.trim().length > 0
      ? assertQuestionReactionId(request.data.qid)
      : "";

  let question;
  try {
    question = normalizeBankRow({
      prompt,
      optA: request.data?.optA,
      optB: request.data?.optB,
      categories: category,
      workSafe: tier === "work-safe",
      mature: tier === "mature",
      shape: request.data?.shape ?? "TASTE",
      active,
    });
  } catch (error) {
    mapRoomValidationError(error);
  }

  const computedQid = bankQuestionIdForPrompt(question.prompt);
  const qid = explicitQid || computedQid;
  if (explicitQid && explicitQid !== computedQid) {
    const duplicate = await db.collection("questionBank").doc(computedQid).get();
    if (duplicate.exists) {
      throw new HttpsError(
        "already-exists",
        "A bank question with this exact prompt already exists.",
      );
    }
  }

  await db.collection("questionBank").doc(qid).set({
    prompt: question.prompt,
    optA: question.optA,
    optB: question.optB,
    tags: question.tags,
    tier: question.tier,
    shape: question.shape,
    active: question.active,
    timesUsed: FieldValue.increment(0),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: uid,
  }, { merge: true });

  return { qid, saved: true, active: question.active };
});

export const setBankQuestionActive = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const qid = assertString(request.data?.qid, "qid");
  const active = request.data?.active === true;
  await db.collection("questionBank").doc(qid).set({
    active,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { qid, active };
});

export const curateWorldDay = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const dailyKey = normalizeDailyKey(request.data?.dailyKey);
  if (!dailyKey) throw new HttpsError("invalid-argument", "dailyKey is required.");
  const todayKey = dailyKeyForEasternDate(new Date());
  if (dailyKey < todayKey) {
    throw new HttpsError("invalid-argument", "World days can only be curated for today or later.");
  }
  const rawQuestions = Array.isArray(request.data?.questions) ? request.data.questions : [];
  if (rawQuestions.length !== ROOM_QUESTIONS_PER_DAY) {
    throw new HttpsError("invalid-argument",
      `Curate exactly ${ROOM_QUESTIONS_PER_DAY} world questions.`);
  }
  await ensureWorldRoom();

  const questions: RoomDayQuestion[] = [];
  for (const raw of rawQuestions as Array<Record<string, unknown>>) {
    const qid = typeof raw?.qid === "string" && raw.qid.length > 0 ? raw.qid : null;
    const requestedThreshold = Number(raw?.threshold ?? 1000);
    const threshold = Math.max(1, Math.min(1000000,
      Number.isFinite(requestedThreshold) ? Math.round(requestedThreshold) : 1000));
    if (qid) {
      const bankSnap = await db.collection("questionBank").doc(qid).get();
      if (!bankSnap.exists) throw new HttpsError("not-found", `Bank question ${qid} not found.`);
      const data = bankSnap.data() ?? {};
      questions.push({
        qid,
        prompt: String(data.prompt ?? ""),
        optA: String(data.optA ?? "Yes"),
        optB: String(data.optB ?? "No"),
        tag: Array.isArray(data.tags) ? String(data.tags[0] ?? "Everyday") : "Everyday",
        shape: String(data.shape ?? "TASTE"),
        tier: String(data.tier ?? "normal"),
        custom: false,
        authorUid: null,
        authorName: null,
        pulled: false,
        threshold,
      });
    } else {
      try {
        const prompt = normalizeCustomQuestionText(raw?.prompt);
        questions.push({
          qid: bankQuestionIdForPrompt(prompt),
          prompt,
          optA: normalizeCustomOption(raw?.optA, "Yes"),
          optB: normalizeCustomOption(raw?.optB, "No"),
          tag: typeof raw?.tag === "string" && raw.tag.trim().length > 0
            ? raw.tag.trim().slice(0, 40)
            : "Everyday",
          shape: "TASTE",
          tier: "normal",
          custom: false,
          authorUid: null,
          authorName: null,
          pulled: false,
          threshold,
        });
      } catch (error) {
        mapRoomValidationError(error);
      }
    }
  }

  const status = dailyKey === todayKey ? "live" : "scheduled";
  await roomDayRef(WORLD_ROOM_ID, dailyKey).set({
    dailyKey,
    status,
    curatedBy: uid,
    questions,
    answerCount: 0,
    answerCounts: {},
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  if (status === "live") {
    await roomRef(WORLD_ROOM_ID).set({
      currentDailyKey: dailyKey,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return { dailyKey, status, questions: questions.length };
});
