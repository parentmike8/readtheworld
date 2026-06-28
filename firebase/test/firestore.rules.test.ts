import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

let testEnv: RulesTestEnvironment;

const projectId = `rtw-rules-${Date.now()}`;
const rules = readFileSync(resolve("firebase/firestore.rules"), "utf8");

function authedDb(uid: string, token: Record<string, unknown> = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules,
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

async function seed(path: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

describe("questions and hidden results", () => {
  it("allows public reads for live or closed questions only", async () => {
    await seed("questions/live-question", { status: "live", prompt: "Live" });
    await seed("questions/closed-question", { status: "closed", prompt: "Closed" });
    await seed("questions/draft-question", { status: "draft", prompt: "Draft" });

    await assertSucceeds(getDoc(doc(anonDb(), "questions/live-question")));
    await assertSucceeds(getDoc(doc(anonDb(), "questions/closed-question")));
    await assertFails(getDoc(doc(anonDb(), "questions/draft-question")));
  });

  it("keeps daily results hidden until the server marks the result closed", async () => {
    await seed("dailyResults/live-question", {
      status: "live",
      optionPcts: { yes: 55 },
    });
    await seed("dailyResults/closed-question", {
      status: "closed",
      optionPcts: { yes: 45 },
    });

    await assertFails(getDoc(doc(anonDb(), "dailyResults/live-question")));
    await assertSucceeds(getDoc(doc(anonDb(), "dailyResults/closed-question")));
  });

  it("allows public reads of live answer totals without exposing counter shards", async () => {
    await seed("questions/live-question", { status: "live", prompt: "Live" });
    await seed("questionCounters/live-question", {
      questionId: "live-question",
      total: 12,
    });
    await seed("questionCounters/live-question/shards/00", {
      total: 12,
      options: { yes: 8, no: 4 },
    });

    await assertSucceeds(getDoc(doc(anonDb(), "questionCounters/live-question")));
    await assertFails(getDoc(doc(anonDb(), "questionCounters/live-question/shards/00")));
    await assertSucceeds(
      getDoc(doc(authedDb("admin", { admin: true }), "questionCounters/live-question/shards/00")),
    );
  });
});

describe("official answers and scoring data", () => {
  it("prevents direct user answer writes while allowing owner reads", async () => {
    await seed("users/alex/answers/q1", {
      questionId: "q1",
      selectedOptionId: "yes",
      predictedShare: 60,
    });

    await assertSucceeds(getDoc(doc(authedDb("alex"), "users/alex/answers/q1")));
    await assertFails(getDoc(doc(authedDb("bea"), "users/alex/answers/q1")));
    await assertFails(
      setDoc(doc(authedDb("alex"), "users/alex/answers/q2"), {
        questionId: "q2",
        selectedOptionId: "no",
        predictedShare: 40,
      }),
    );
    await assertSucceeds(
      setDoc(doc(authedDb("admin", { admin: true }), "users/alex/answers/q2"), {
        questionId: "q2",
        selectedOptionId: "no",
        predictedShare: 40,
      }),
    );
  });

  it("blocks clients from mutating server-owned score fields", async () => {
    await seed("users/alex", {
      displayName: "Alex",
      readScore: 1500,
      officialQuestionsAnswered: 1,
      readScorePercentile: 91,
      currentStreak: 2,
      leaderboardRank: 5,
      averagePredictionBias: 3,
      predictionBiasDirection: "over",
    });

    await assertSucceeds(
      updateDoc(doc(authedDb("alex"), "users/alex"), {
        displayName: "Alex P.",
        dailyReminder: true,
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb("alex"), "users/alex"), {
        readScore: 1600,
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb("alex"), "users/alex"), {
        leaderboardRank: 1,
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb("alex"), "users/alex"), {
        averagePredictionBias: -8,
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb("alex"), "users/alex"), {
        customClientField: "nope",
      }),
    );
  });
});

describe("admin, links, invites, and leaderboards", () => {
  it("allows only admins to write questions and leaderboards", async () => {
    await assertFails(
      setDoc(doc(authedDb("alex"), "questions/q1"), {
        status: "draft",
        prompt: "Draft",
      }),
    );
    await assertSucceeds(
      setDoc(doc(authedDb("admin", { admin: true }), "questions/q1"), {
        status: "draft",
        prompt: "Draft",
      }),
    );
    await assertFails(
      setDoc(doc(authedDb("alex"), "leaderboards/global/rows/alex"), {
        readScore: 1600,
      }),
    );
    await assertSucceeds(
      setDoc(doc(authedDb("admin", { admin: true }), "leaderboards/global/rows/alex"), {
        readScore: 1600,
      }),
    );
  });

  it("keeps short-link and invite metadata server-owned", async () => {
    await assertFails(
      setDoc(doc(authedDb("alex"), "links/ABC123"), {
        type: "invite",
        targetId: "alex",
        createdBy: "alex",
      }),
    );
    await assertFails(
      setDoc(doc(authedDb("alex"), "invites/ABC123"), {
        createdBy: "alex",
        status: "active",
      }),
    );
    await assertSucceeds(
      setDoc(doc(authedDb("admin", { admin: true }), "links/ABC123"), {
        type: "invite",
        targetId: "alex",
        createdBy: "alex",
      }),
    );
    await assertSucceeds(
      setDoc(doc(authedDb("admin", { admin: true }), "invites/ABC123"), {
        createdBy: "alex",
        status: "active",
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb("alex"), "invites/ABC123"), {
        status: "revoked",
      }),
    );
  });

  it("keeps notification campaign audits admin-only", async () => {
    await seed("notificationCampaigns/c1", {
      title: "Today's question is live",
      audience: "all",
    });

    await assertFails(getDoc(doc(authedDb("alex"), "notificationCampaigns/c1")));
    await assertSucceeds(getDoc(doc(authedDb("admin", { admin: true }), "notificationCampaigns/c1")));
    await assertFails(
      setDoc(doc(authedDb("alex"), "notificationCampaigns/c2"), {
        title: "Nope",
      }),
    );
    await assertSucceeds(
      setDoc(doc(authedDb("admin", { admin: true }), "notificationCampaigns/c2"), {
        title: "Allowed",
      }),
    );
  });

  it("keeps user deletes admin-only so clearMyData owns cleanup", async () => {
    await seed("users/alex", { displayName: "Alex" });

    await assertFails(deleteDoc(doc(authedDb("alex"), "users/alex")));
    await assertFails(deleteDoc(doc(authedDb("bea"), "users/alex")));
    await assertSucceeds(deleteDoc(doc(authedDb("admin", { admin: true }), "users/alex")));
  });

  it("keeps friendship mutations server-owned", async () => {
    await seed("users/alex/friends/bea", {
      uid: "bea",
      displayName: "Bea",
      answersShared: false,
      status: "active",
    });

    await assertSucceeds(getDoc(doc(authedDb("alex"), "users/alex/friends/bea")));
    await assertFails(
      updateDoc(doc(authedDb("alex"), "users/alex/friends/bea"), {
        answersShared: true,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("admin", { admin: true }), "users/alex/friends/bea"), {
        answersShared: true,
      }),
    );
  });

  it("limits notification token writes to owner-controlled token fields", async () => {
    await assertSucceeds(
      setDoc(doc(authedDb("alex"), "users/alex/notificationTokens/token1"), {
        token: "token-1",
        platform: "iOS",
        enabled: true,
        updatedAt: 1,
      }),
    );
    await assertFails(
      setDoc(doc(authedDb("bea"), "users/alex/notificationTokens/token2"), {
        token: "token-2",
        platform: "web",
        enabled: true,
        updatedAt: 1,
      }),
    );
    await assertFails(
      setDoc(doc(authedDb("alex"), "users/alex/notificationTokens/token3"), {
        token: "token-3",
        platform: "web",
        enabled: true,
        disabledReason: "client-controlled",
        updatedAt: 1,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("alex"), "users/alex/notificationTokens/token1"), {
        enabled: false,
        updatedAt: 2,
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb("alex"), "users/alex/notificationTokens/token1"), {
        disabledReason: "client-controlled",
      }),
    );
  });

  it("does not allow clients to write waitlist records directly", async () => {
    await assertFails(
      setDoc(doc(anonDb(), "waitlist/hash"), {
        email: "alex@example.com",
      }),
    );
    await assertFails(
      setDoc(doc(authedDb("alex"), "waitlist/hash"), {
        email: "alex@example.com",
      }),
    );
  });
});

describe("test harness", () => {
  it("starts with the expected emulator-backed project", () => {
    expect(projectId).toContain("rtw-rules-");
  });
});
