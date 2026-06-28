import { createHash, randomBytes } from "crypto";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getMessaging } from "firebase-admin/messaging";
import { getRemoteConfig } from "firebase-admin/remote-config";
import {
  FieldValue,
  type DocumentReference,
  type DocumentData,
  type Query,
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
import { buildSeedQuestionSchedule } from "./seedQuestions";
import {
  isShortLinkType,
  shortLinkExpired,
  shortLinkExpiresAt,
  type ShortLinkType,
} from "./links";
import { decideDailyOpen } from "./lifecycle";
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
  ADMIN_FEATURE_FLAGS,
  adminFeatureFlagDefinition,
  remoteConfigBooleanValue,
  remoteConfigParameterBooleanValue,
  type AdminFeatureFlagKey,
} from "./config";
import { resultIsRevealed } from "./visibility";
import { isPracticeAnswerSource } from "./practice";

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

function assertString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
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

export const submitPrediction = onCall(async (request) => {
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
    const counterRef = db
      .collection("questionCounters")
      .doc(questionId)
      .collection("shards")
      .doc(counterShard);

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

    return {
      locked: true,
      questionId,
      selectedOptionId,
      predictedShare,
    };
  });

  return result;
});

export const savePracticeAnswer = onCall(async (request) => {
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

export const clearMyData = onCall(async (request) => {
  const uid = requireUid(request.auth);
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
    leaderboardRank: FieldValue.delete(),
    leaderboardUpdatedAt: FieldValue.delete(),
    clearedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true }));
  await commitBatchedWrites(cleanupWrites);
  const shareData = await clearServerOwnedShareData(uid);

  const deleted = {
    answers: await deleteUserSubcollection(uid, "answers"),
    scoreHistory: await deleteUserSubcollection(uid, "scoreHistory"),
    categoryStats: await deleteUserSubcollection(uid, "categoryStats"),
    friends: await deleteUserSubcollection(uid, "friends"),
    links: shareData.links,
    invitesCreated: shareData.invitesCreated,
    invitesAcceptedUpdated: shareData.invitesAcceptedUpdated,
  };
  await recomputeGlobalLeaderboard();
  return { cleared: true, deleted };
});

export const joinWaitlist = onCall(async (request) => {
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

export const listWaitlist = onCall(async (request) => {
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

export const getAdminOverview = onCall(async (request) => {
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

export const getAdminAppConfig = onCall(async (request) => {
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

export const setAdminFeatureFlag = onCall(async (request) => {
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

export const createInvite = onCall(async (request) => {
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

export const createShareLink = onCall(async (request) => {
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

export const acceptInvite = onCall(async (request) => {
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

export const resolveShortCode = onCall(async (request) => {
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

  const route = type === "invite"
    ? `/invite/${code}`
    : `/reveal/${encodeURIComponent(targetId)}?code=${encodeURIComponent(code)}`;
  return { code, type, targetId, route };
});

export const setFriendAnswerVisibility = onCall(async (request) => {
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

export const removeFriend = onCall(async (request) => {
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

export const getLeaderboard = onCall(async (request) => {
  requireUid(request.auth);
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

export const recomputeLeaderboardsNow = onCall(async (request) => {
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
  schedule: "55 7 * * *",
  timeZone: EASTERN_TIME_ZONE,
}, async () => {
  const tokens = await activeNotificationTokens();
  const result = await sendNotificationToTokens(
    tokens,
    dailyNotificationPayload("daily_question"),
  );

  logger.info("Sent daily notifications", {
    ...result,
  });
});

export const sendRevealReadyNotifications = onSchedule({
  schedule: "10 0 * * *",
  timeZone: EASTERN_TIME_ZONE,
}, async () => {
  const tokens = await activeNotificationTokens();
  const result = await sendNotificationToTokens(
    tokens,
    dailyNotificationPayload("result_ready"),
  );

  logger.info("Sent reveal-ready notifications", {
    ...result,
  });
});

export const sendBroadcastNotification = onCall(async (request) => {
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
  const destination = type === "invite"
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

export const upsertQuestion = onCall(async (request) => {
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

export const closeQuestionNow = onCall(async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const questionId = assertString(request.data?.questionId, "questionId");
  return closeQuestion(questionId, true);
});

export const recomputeQuestion = onCall(async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);
  const questionId = assertString(request.data?.questionId, "questionId");
  return closeQuestion(questionId, true);
});

export const seedInitialQuestions = onCall(async (request) => {
  const uid = requireUid(request.auth);
  await requireAdmin(uid);

  let scheduledSeedQuestions;
  try {
    scheduledSeedQuestions = buildSeedQuestionSchedule({
      startDailyKey: normalizeDailyKey(request.data?.startDailyKey),
    });
  } catch (error) {
    mapQuestionValidationError(error);
  }

  const firstQuestionId = scheduledSeedQuestions[0]?.id ?? null;
  const liveQuestions = await db
    .collection("questions")
    .where("status", "==", "live")
    .limit(5)
    .get();
  const conflictingLiveQuestions = liveQuestions.docs
    .map((doc) => doc.id)
    .filter((questionId) => questionId !== firstQuestionId);
  if (conflictingLiveQuestions.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      "A live question already exists. Close it before seeding initial questions.",
    );
  }

  const refs = scheduledSeedQuestions.map((question) => db.collection("questions").doc(question.id));
  const existing = await Promise.all(refs.map((ref) => ref.get()));
  const batch = db.batch();
  let seeded = 0;
  let skipped = 0;
  scheduledSeedQuestions.forEach((question, index) => {
    if (existing[index]?.exists) {
      skipped += 1;
      return;
    }
    seeded += 1;
    batch.set(refs[index], {
      category: question.category,
      prompt: question.prompt,
      options: question.options,
      type: question.type,
      status: question.status,
      dailyKey: question.dailyKey,
      publishAt: Timestamp.fromDate(question.publishAt),
      closeAt: Timestamp.fromDate(question.closeAt),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  if (seeded > 0) {
    await batch.commit();
  }
  return {
    seeded,
    skipped,
    total: scheduledSeedQuestions.length,
    startDailyKey: scheduledSeedQuestions[0]?.dailyKey ?? null,
    firstQuestionId,
  };
});
