"use client";

import { FirebaseError, getApps, initializeApp } from "firebase/app";
import {
  GoogleAuthProvider,
  getAuth,
  getIdTokenResult,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
  type User,
} from "firebase/auth";
import {
  collection,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
  type DocumentData,
  type QueryDocumentSnapshot,
} from "firebase/firestore";
import { getFunctions, httpsCallable } from "firebase/functions";
import {
  BarChart3,
  Bell,
  CalendarDays,
  CheckCircle2,
  CircleDot,
  ClipboardList,
  Download,
  Eye,
  Library,
  RefreshCw,
  Save,
  SlidersHorizontal,
  UploadCloud,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";

type AdminState = "missing-config" | "signed-out" | "checking" | "authorized" | "unauthorized";
export type AdminView = "today" | "schedule" | "library" | "analytics" | "results" | "notifications" | "settings";
type BroadcastAudience = "all" | "streak_at_risk" | "lapsed_7d";
type LibraryFilter = "All" | "Live" | "Scheduled" | "Used" | "Draft";
type QuestionOption = {
  id: string;
  label: string;
};
type AdminQuestion = {
  id: string;
  prompt: string;
  category: string;
  status: string;
  dailyKey: string;
  publishAt: string;
  closeAt: string;
  options: QuestionOption[];
};
type WaitlistEntry = {
  id: string;
  email: string;
  source: string;
  answer: string | null;
  predictedShare: number | null;
  signupCount: number;
  uid: string | null;
  createdAt: string | null;
  latestAt: string | null;
};
type AdminFeatureFlag = {
  key: string;
  label: string;
  description: string;
  enabled: boolean;
};
type AdminMetricSummary = {
  totalUsers: number;
  activeUsers: number;
  newUsers7d: number;
  waitlistSignups: number;
  notificationTokens: number;
  leaderboardRows: number;
  answersToday: number;
  predictionsLocked: number;
  avgStreak: number;
  activeStreaks: number;
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
type AdminOverview = {
  generatedAt: string;
  metrics: AdminMetricSummary;
  questions: AdminQuestion[];
  results: AdminResultSummary[];
  focusResult: AdminResultSummary | null;
  liveCounters: {
    questionId: string;
    totalAnswers: number;
    optionCounts: Record<string, number>;
    optionPcts: Record<string, number>;
  } | null;
  dailyActivity: Array<{ label: string; value: number }>;
  categoryRows: Array<{ category: string; value: number; answers: number }>;
  retentionRows: Array<{ label: string; value: number }>;
  audience: {
    age: Array<{ label: string; value: number; count: number }>;
    gender: Array<{ label: string; value: number; count: number }>;
    country: Array<{ label: string; value: number; count: number }>;
  };
};

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const allowedAdminEmail = "mike@readtheworld.today";

const navItems: Array<{ id: AdminView; label: string; icon: ReactNode }> = [
  { id: "today", label: "Today", icon: <CircleDot size={15} /> },
  { id: "schedule", label: "Schedule", icon: <CalendarDays size={15} /> },
  { id: "library", label: "Library", icon: <Library size={15} /> },
  { id: "analytics", label: "Analytics", icon: <BarChart3 size={15} /> },
  { id: "results", label: "Results", icon: <ClipboardList size={15} /> },
  { id: "notifications", label: "Notifications", icon: <Bell size={15} /> },
  { id: "settings", label: "Settings", icon: <SlidersHorizontal size={15} /> },
];

const broadcastAudiences: Array<{ id: BroadcastAudience; label: string }> = [
  { id: "all", label: "Everyone" },
  { id: "streak_at_risk", label: "Streak at risk" },
  { id: "lapsed_7d", label: "Lapsed 7d" },
];

const sampleFeatureFlags: AdminFeatureFlag[] = [
  {
    key: "feature_party_mode",
    label: "Party mode",
    description: "Group play with past questions on a shared screen",
    enabled: true,
  },
  {
    key: "feature_friends",
    label: "Friends & social",
    description: "Add friends, compare reads, share results",
    enabled: true,
  },
  {
    key: "feature_friends_leaderboard",
    label: "Friends leaderboard",
    description: "Rank friends by Read Score",
    enabled: true,
  },
  {
    key: "feature_result_sharing",
    label: "Shareable result cards",
    description: "Let users share their daily read",
    enabled: true,
  },
  {
    key: "feature_onboarding_demographics",
    label: "Onboarding demographics",
    description: "Collect optional birthdate, gender, and country at sign-up",
    enabled: true,
  },
];

const sampleQuestions: AdminQuestion[] = [
  {
    id: "2026-06-01-technology-ai-labels",
    prompt: "Should AI-generated content be labeled by law?",
    category: "TECHNOLOGY",
    status: "closed",
    dailyKey: "2026-06-01",
    publishAt: "2026-06-01T00:00:00-04:00",
    closeAt: "2026-06-02T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-02-money-happiness",
    prompt: "Can money buy happiness?",
    category: "MONEY",
    status: "closed",
    dailyKey: "2026-06-02",
    publishAt: "2026-06-02T00:00:00-04:00",
    closeAt: "2026-06-03T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-03-culture-hot-dog",
    prompt: "Is a hot dog a sandwich?",
    category: "CULTURE",
    status: "closed",
    dailyKey: "2026-06-03",
    publishAt: "2026-06-03T00:00:00-04:00",
    closeAt: "2026-06-04T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-04-society-social-media",
    prompt: "Would the world be better without social media?",
    category: "SOCIETY",
    status: "closed",
    dailyKey: "2026-06-04",
    publishAt: "2026-06-04T00:00:00-04:00",
    closeAt: "2026-06-05T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-05-philosophy-free-will",
    prompt: "Do you believe in free will?",
    category: "PHILOSOPHY",
    status: "closed",
    dailyKey: "2026-06-05",
    publishAt: "2026-06-05T00:00:00-04:00",
    closeAt: "2026-06-06T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-06-science-phone-week",
    prompt: "Could you go a week without your phone?",
    category: "SCIENCE",
    status: "closed",
    dailyKey: "2026-06-06",
    publishAt: "2026-06-06T00:00:00-04:00",
    closeAt: "2026-06-07T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-07-health-breakfast",
    prompt: "Is breakfast the most important meal?",
    category: "HEALTH",
    status: "closed",
    dailyKey: "2026-06-07",
    publishAt: "2026-06-07T00:00:00-04:00",
    closeAt: "2026-06-08T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-08-ethics-honesty",
    prompt: "Is honesty always the best policy?",
    category: "ETHICS",
    status: "closed",
    dailyKey: "2026-06-08",
    publishAt: "2026-06-08T00:00:00-04:00",
    closeAt: "2026-06-09T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-25-philosophy-death-date",
    prompt: "Would you want to know the exact date you'll die?",
    category: "PHILOSOPHY",
    status: "live",
    dailyKey: "2026-06-25",
    publishAt: "2026-06-25T00:00:00-04:00",
    closeAt: "2026-06-26T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-26-culture-phones-dinner",
    prompt: "Is it rude to keep your phone on the table at dinner?",
    category: "CULTURE",
    status: "scheduled",
    dailyKey: "2026-06-26",
    publishAt: "2026-06-26T00:00:00-04:00",
    closeAt: "2026-06-27T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-27-society-billionaires",
    prompt: "Should billionaires exist?",
    category: "SOCIETY",
    status: "scheduled",
    dailyKey: "2026-06-27",
    publishAt: "2026-06-27T00:00:00-04:00",
    closeAt: "2026-06-28T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "2026-06-17-technology-ai-labels",
    prompt: "Should AI-generated content be labeled by law?",
    category: "TECHNOLOGY",
    status: "closed",
    dailyKey: "2026-06-17",
    publishAt: "2026-06-17T00:00:00-04:00",
    closeAt: "2026-06-18T00:00:00-04:00",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "draft-ethics-lie-feelings",
    prompt: "Is it ever okay to lie to protect someone's feelings?",
    category: "ETHICS",
    status: "draft",
    dailyKey: "",
    publishAt: "",
    closeAt: "",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "draft-science-mars",
    prompt: "Will humans live on Mars within 50 years?",
    category: "SCIENCE",
    status: "draft",
    dailyKey: "",
    publishAt: "",
    closeAt: "",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "draft-society-remote-office",
    prompt: "Is remote work better than the office?",
    category: "SOCIETY",
    status: "draft",
    dailyKey: "",
    publishAt: "",
    closeAt: "",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
  {
    id: "draft-philosophy-luck-hard-work",
    prompt: "Does luck matter more than hard work?",
    category: "PHILOSOPHY",
    status: "draft",
    dailyKey: "",
    publishAt: "",
    closeAt: "",
    options: [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ],
  },
];

const emptyAdminQuestion: AdminQuestion = {
  id: "",
  prompt: "No question is loaded yet.",
  category: "DAILY READ",
  status: "",
  dailyKey: "",
  publishAt: "",
  closeAt: "",
  options: [],
};

const categoryColors: Record<string, string> = {
  TECHNOLOGY: "#3E5BA0",
  SOCIETY: "#B06A47",
  CULTURE: "#B48D3D",
  PHILOSOPHY: "#7B61A5",
  MONEY: "#4E875B",
  SCIENCE: "#3C8796",
  HEALTH: "#B46C73",
  ETHICS: "#697180",
};

function hasFirebaseConfig() {
  return Object.values(firebaseConfig).every(Boolean);
}

const devAdminPreview =
  process.env.NODE_ENV !== "production" &&
  process.env.NEXT_PUBLIC_ADMIN_PREVIEW === "true";

export function AdminPanel({ initialView = "today" }: { initialView?: AdminView }) {
  const [user, setUser] = useState<User | null>(null);
  const [state, setState] = useState<AdminState>(hasFirebaseConfig() ? "checking" : "missing-config");
  const [activeView, setActiveView] = useState<AdminView>(initialView);
  const [checkingClaims, setCheckingClaims] = useState(false);
  const [libraryFilter, setLibraryFilter] = useState<LibraryFilter>("All");
  const [questionEditorOpen, setQuestionEditorOpen] = useState(false);
  const [questions, setQuestions] = useState<AdminQuestion[]>([]);
  const [activeQuestionId, setActiveQuestionId] = useState("");
  const [questionId, setQuestionId] = useState("");
  const [prompt, setPrompt] = useState("");
  const [category, setCategory] = useState("");
  const [status, setStatus] = useState("draft");
  const [dailyKey, setDailyKey] = useState("");
  const [publishAt, setPublishAt] = useState("");
  const [closeAt, setCloseAt] = useState("");
  const [options, setOptions] = useState<QuestionOption[]>([
    { id: "yes", label: "Yes" },
    { id: "no", label: "No" },
  ]);
  const [waitlist, setWaitlist] = useState<WaitlistEntry[]>([]);
  const [loadingWaitlist, setLoadingWaitlist] = useState(false);
  const [overview, setOverview] = useState<AdminOverview | null>(null);
  const [loadingOverview, setLoadingOverview] = useState(false);
  const [featureFlags, setFeatureFlags] = useState<AdminFeatureFlag[]>([]);
  const [broadcastTitle, setBroadcastTitle] = useState("Today's question is live 🌍");
  const [broadcastBody, setBroadcastBody] = useState("Can you read the world today? Tap to answer and lock your prediction before the reveal.");
  const [broadcastAudience, setBroadcastAudience] = useState<BroadcastAudience>("all");
  const broadcastRoute = "/today";
  const [message, setMessage] = useState("");
  const [busyAction, setBusyAction] = useState("");

  const app = useMemo(() => {
    if (!hasFirebaseConfig()) return null;
    return getApps()[0] ?? initializeApp(firebaseConfig);
  }, []);

  const auth = app ? getAuth(app) : null;
  const firestore = app ? getFirestore(app) : null;
  const functions = app ? getFunctions(app, "us-central1") : null;
  const adminUnlocked = state === "authorized" || devAdminPreview;
  const overviewQuestions = overview?.questions ?? [];
  const liveRows = questions.length > 0 ? questions : overviewQuestions;
  const rows = liveRows.length > 0 ? liveRows : devAdminPreview ? sampleQuestions : [];
  const scheduleRows = devAdminPreview && questions.length === 0 ? calendarPreviewQuestions(rows) : rows;
  const liveQuestion =
    rows.find((question) => question.status === "live") ?? rows[0] ?? emptyAdminQuestion;
  const nextQuestion =
    rows.find((question) => question.status === "scheduled") ?? (devAdminPreview ? sampleQuestions[1] : emptyAdminQuestion);
  const focusedResult = overview?.focusResult ?? overview?.results[0] ?? null;
  const resultsQuestion = focusedResult ? resultAsQuestion(focusedResult) : liveQuestion;
  const liveDonut = donutForQuestion(liveQuestion, overview);
  const resultDonut = focusedResult ? donutForResult(focusedResult) : liveDonut;
  const displayName = user?.displayName || user?.email?.split("@")[0] || "Admin";
  const displayInitial = displayName.trim().slice(0, 1).toUpperCase() || "A";

  const loadOverview = useCallback(async (focusQuestionId?: string) => {
    if (!functions) return;
    if (devAdminPreview) {
      setOverview(null);
      return;
    }
    setLoadingOverview(true);
    setMessage("");
    try {
      const callable = httpsCallable(functions, "getAdminOverview");
      const result = await callable({ questionId: focusQuestionId || undefined });
      setOverview(adminOverviewFromData(result.data));
    } catch (error) {
      const text = error instanceof FirebaseError ? error.message : String(error);
      setMessage(text);
    } finally {
      setLoadingOverview(false);
    }
  }, [functions]);

  const loadAdminAppConfig = useCallback(async () => {
    if (!functions) return;
    if (devAdminPreview) {
      setFeatureFlags([]);
      return;
    }
    try {
      const callable = httpsCallable(functions, "getAdminAppConfig");
      const result = await callable();
      const data = objectValue(result.data);
      setFeatureFlags(arrayValue(data.flags).map(featureFlagFromData));
    } catch (error) {
      const text = error instanceof FirebaseError ? error.message : String(error);
      setMessage(text);
    }
  }, [functions]);

  const refreshAdminClaim = useCallback(async (nextUser: User | null) => {
    if (!nextUser) return;
    setCheckingClaims(true);
    try {
      const emailAllowed = nextUser.email?.toLowerCase() === allowedAdminEmail;
      const googleSignedIn = nextUser.providerData.some((provider) => provider.providerId === "google.com");
      if (!emailAllowed || !googleSignedIn) {
        setState("unauthorized");
        setOverview(null);
        setFeatureFlags([]);
        return;
      }
      const token = await getIdTokenResult(nextUser, true);
      const authorized = token.claims.admin === true || emailAllowed;
      setState(authorized ? "authorized" : "unauthorized");
      if (authorized) {
        await Promise.all([loadOverview(), loadAdminAppConfig()]);
      } else {
        setOverview(null);
        setFeatureFlags([]);
      }
    } catch (error) {
      const text = error instanceof FirebaseError ? error.message : String(error);
      setMessage(text);
      setState("unauthorized");
      setOverview(null);
      setFeatureFlags([]);
    } finally {
      setCheckingClaims(false);
    }
  }, [loadAdminAppConfig, loadOverview]);

  useEffect(() => {
    if (!auth) return;
    return onAuthStateChanged(auth, async (nextUser) => {
      setUser(nextUser);
      if (!nextUser) {
        setQuestions([]);
        setWaitlist([]);
        setOverview(null);
        setFeatureFlags([]);
        setLoadingWaitlist(false);
        setLoadingOverview(false);
        setState("signed-out");
        return;
      }
      setState("checking");
      await refreshAdminClaim(nextUser);
    });
  }, [auth, refreshAdminClaim]);

  useEffect(() => {
    if (!firestore || state !== "authorized" || devAdminPreview) return;
    const questionsQuery = query(collection(firestore, "questions"), orderBy("dailyKey", "desc"), limit(30));
    return onSnapshot(
      questionsQuery,
      (snapshot) => {
        const nextQuestions = snapshot.docs.map(questionFromSnapshot);
        setQuestions(nextQuestions);
      },
      (error) => {
        setMessage(error.message);
      },
    );
  }, [firestore, state]);

  async function runCallable(name: string, payload: Record<string, unknown> = {}) {
    if (!functions) return;
    const validation = validatePayload(name, payload);
    if (validation) {
      setMessage(validation);
      return;
    }
    setMessage("");
    setBusyAction(name);
    try {
      const callable = httpsCallable(functions, name);
      const result = await callable(payload);
      setMessage(JSON.stringify(result.data, null, 2));
      if (name !== "listWaitlist") {
        await loadOverview(activeQuestionId);
      }
      if (name === "setAdminFeatureFlag") {
        await loadAdminAppConfig();
      }
    } catch (error) {
      const text = error instanceof FirebaseError ? error.message : String(error);
      setMessage(text);
    } finally {
      setBusyAction("");
    }
  }

  async function login() {
    if (!auth) return;
    const provider = new GoogleAuthProvider();
    provider.setCustomParameters({
      login_hint: allowedAdminEmail,
      prompt: "select_account",
    });
    await signInWithPopup(auth, provider);
  }

  function startNewQuestion() {
    resetQuestionForm();
    setQuestionEditorOpen(true);
  }

  function updateOption(index: number, field: keyof QuestionOption, value: string) {
    setOptions((current) =>
      current.map((option, optionIndex) =>
        optionIndex === index ? { ...option, [field]: value } : option,
      ),
    );
  }

  function normalizedOptions() {
    return options
      .map((option) => ({
        id: option.id.trim().toLowerCase().replace(/\s+/g, "-"),
        label: option.label.trim(),
      }))
      .filter((option) => option.id && option.label);
  }

  function resetQuestionForm() {
    setActiveQuestionId("");
    setQuestionId("");
    setPrompt("");
    setCategory("");
    setStatus("draft");
    setDailyKey("");
    setPublishAt("");
    setCloseAt("");
    setOptions([
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ]);
  }

  function applyQuestion(question: AdminQuestion) {
    setQuestionEditorOpen(true);
    setActiveQuestionId(question.id);
    setQuestionId(question.id);
    setPrompt(question.prompt);
    setCategory(question.category);
    setStatus(question.status);
    setDailyKey(question.dailyKey);
    setPublishAt(question.publishAt);
    setCloseAt(question.closeAt);
    setOptions(question.options.length >= 2 ? question.options : [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ]);
    if (state === "authorized") {
      void loadOverview(question.id);
    }
  }

  function questionPayload(statusOverride?: string) {
    return {
      questionId,
      prompt,
      category,
      dailyKey,
      status: statusOverride ?? status,
      publishAt,
      closeAt,
      options: normalizedOptions(),
    };
  }

  async function loadWaitlist() {
    if (!functions) return;
    setLoadingWaitlist(true);
    setMessage("");
    try {
      const callable = httpsCallable(functions, "listWaitlist");
      const result = await callable({ limit: 100 });
      const data = result.data as { rows?: unknown[] };
      setWaitlist((data.rows ?? []).map(waitlistEntryFromData));
    } catch (error) {
      const text = error instanceof FirebaseError ? error.message : String(error);
      setMessage(text);
    } finally {
      setLoadingWaitlist(false);
    }
  }

  function exportWaitlistCsv() {
    const rowsForCsv = [
      ["email", "source", "answer", "predictedShare", "signupCount", "createdAt", "latestAt", "uid"],
      ...waitlist.map((entry) => [
        entry.email,
        entry.source,
        entry.answer ?? "",
        entry.predictedShare == null ? "" : String(entry.predictedShare),
        String(entry.signupCount),
        entry.createdAt ?? "",
        entry.latestAt ?? "",
        entry.uid ?? "",
      ]),
    ];
    const csv = rowsForCsv.map((row) => row.map(csvCell).join(",")).join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `read-the-world-waitlist-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  function renderContent() {
    if (!adminUnlocked) {
      return renderAccessGate();
    }

    if (!devAdminPreview && !overview) {
      return renderLiveDataGate();
    }

    switch (activeView) {
      case "schedule":
        return renderSchedule();
      case "library":
        return renderLibrary();
      case "analytics":
        return renderAnalytics();
      case "results":
        return renderResults();
      case "notifications":
        return renderNotifications();
      case "settings":
        return renderSettings();
      case "today":
      default:
        return renderToday();
    }
  }

  function renderLiveDataGate() {
    return (
      <div className="adminDesignPanel adminGate">
        <div>
          <div className="adminKicker">Live data</div>
          <h1 className="adminSerif">
            {loadingOverview || checkingClaims ? "Loading admin data." : "Admin data is not available."}
          </h1>
          <p>
            {message || "The admin portal is waiting for the production Firebase overview response."}
          </p>
        </div>
        <div className="adminLoginGrid">
          <button className="adminBlueButton" disabled={loadingOverview} onClick={() => loadOverview(activeQuestionId)}>
            {loadingOverview ? "Loading..." : "Refresh live data"}
          </button>
        </div>
      </div>
    );
  }

  function renderAccessGate() {
    const configMissing = state === "missing-config";
    const signedInAs = user?.email ?? null;
    const isWrongEmail = signedInAs != null && signedInAs.toLowerCase() !== allowedAdminEmail;
    const isWrongProvider = user != null && !user.providerData.some((provider) => provider.providerId === "google.com");
    return (
      <div className="adminDesignPanel adminGate">
        <div>
          <div className="adminKicker">Admin access</div>
          <h1 className="adminSerif">{configMissing ? "Firebase config needed." : "Sign in to manage Read the World."}</h1>
          <p>
            {configMissing
              ? "Add the NEXT_PUBLIC_FIREBASE values from the isolated Read the World Firebase project before using admin."
              : `Use Google sign-in as ${allowedAdminEmail}.`}
          </p>
        </div>
        {!configMissing ? (
          <div className="adminLoginGrid">
            <button className="adminBlueButton adminGoogleButton" onClick={login}>
              <span>G</span> Continue with Google
            </button>
            {state === "checking" ? <p>Checking your admin session...</p> : null}
            {state === "unauthorized" ? (
              <p>
                {isWrongEmail
                  ? `Only ${allowedAdminEmail} is allowed right now. You are signed in as ${signedInAs}.`
                  : isWrongProvider
                    ? "Admin currently requires Google sign-in."
                    : "This Google account is allowed, but it still needs the Firebase admin custom claim."}
              </p>
            ) : null}
            {user ? (
              <button className="adminGhostButton" onClick={() => auth && signOut(auth)}>
                Sign out
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
    );
  }

  function renderToday() {
    const metrics = overview?.metrics;
    const dailyActivity = overview?.dailyActivity ?? [];
    return (
      <>
        <div className="adminViewHead">
          <div>
            <div className="adminKicker adminLiveKicker">Live now · {longDate(liveQuestion.dailyKey) ?? "Today"}</div>
            <h1 className="adminSerif">Today at a glance</h1>
          </div>
          <div className="adminRevealClock">
            <span>Reveal in</span>
            <strong>{devAdminPreview ? "6h 24m" : timeUntil(liveQuestion.closeAt) ?? "--"}</strong>
          </div>
        </div>

        <section className="adminHeroCard">
          <div>
            <div className="adminKicker">
              <CategoryDot category={liveQuestion.category} /> {displayCategory(liveQuestion.category)} · Today&apos;s question
            </div>
            <h2 className="adminSerif">{liveQuestion.prompt}</h2>
            <div className="adminHeroActions">
              <button className="adminBlueButton" onClick={() => setActiveView("results")}>
                View live results
              </button>
              <button onClick={() => {
                applyQuestion(liveQuestion);
                setActiveView("library");
              }}>
                Edit question
              </button>
            </div>
          </div>
          <ResultDonut {...liveDonut} />
        </section>

        <div className="adminMetricGrid">
          <MetricCard
            label="Answers today"
            value={formatCount(metrics?.answersToday, devAdminPreview ? "1,640" : "0")}
            detail={`${formatPercentOf(metrics?.answersToday, metrics?.activeUsers, devAdminPreview ? "87%" : "0%")} of active users`}
          />
          <MetricCard
            label="Predictions locked"
            value={formatCount(metrics?.predictionsLocked, devAdminPreview ? "1,512" : "0")}
            detail={focusedResult?.avgPredictedShare == null ? "Avg guess --" : `Avg guess ${focusedResult.avgPredictedShare}%`}
          />
          <MetricCard
            label="Daily active"
            value={formatCount(metrics?.activeUsers, devAdminPreview ? "1,892" : "0")}
            detail={devAdminPreview || metrics == null ? "+3.4% vs yesterday" : `${formatCount(metrics.leaderboardRows)} ranked readers`}
          />
          <MetricCard
            label="New users"
            value={formatCount(metrics?.newUsers7d, devAdminPreview ? "47" : "0")}
            detail={`${formatCount(metrics?.totalUsers, devAdminPreview ? "3,247" : "0")} total`}
          />
        </div>

        <div className="adminTodayLower">
          <section className="adminDesignPanel">
            <PanelHeader label="Answers through the day" meta={dailyActivity.length > 0 ? `${dailyActivity.length} recent closes` : "00:00 → now"} />
            <Sparkline preview={devAdminPreview} values={dailyActivity.map((item) => item.value)} />
          </section>
          <section className="adminNextCard">
            <div className="adminKicker">Up next · Tomorrow</div>
            <div className="adminNextCategory">
              <CategoryDot category={nextQuestion.category} />
              <span>{displayCategory(nextQuestion.category)}</span>
            </div>
            <h3 className="adminSerif">{nextQuestion.prompt}</h3>
            <button onClick={() => setActiveView("schedule")}>Open schedule</button>
          </section>
        </div>
      </>
    );
  }

  function renderSchedule() {
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Schedule</h1>
            <p>Assign one question to each day. Gaps are flagged in red.</p>
          </div>
          <div className="adminToolbar">
            <button>Current schedule</button>
              <button className="adminBlueButton" onClick={() => {
              startNewQuestion();
              setActiveView("library");
            }}>
              + New question
            </button>
          </div>
        </div>
        <div className="adminScheduleGrid">
          <section>
            <div className="adminWeekdays">
              {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((day) => (
                <span key={day}>{day}</span>
              ))}
            </div>
            <div className="adminCalendar">
              {Array.from({ length: 35 }, (_, index) => {
                const day = index;
                if (day === 0 || day > 30) {
                  return <div className="adminCalendarSpacer" key={`blank-${index}`} />;
                }
                const item = questionForDay(scheduleRows, day);
                const needsQuestion = devAdminPreview ? day >= 28 : !item;
                return (
                  <button
                    className={item?.status === "live" ? "live" : needsQuestion ? "needsQuestion" : ""}
                    key={day}
                    onClick={() => item && applyQuestion(item)}
                  >
                    <span>{day}</span>
                    {item ? (
                      <strong>
                        <CategoryDot category={item.category} /> {item.prompt}
                      </strong>
                    ) : needsQuestion ? (
                      <em>Needs Q</em>
                    ) : null}
                  </button>
                );
              })}
            </div>
          </section>
          <aside className="adminDrafts">
            <div className="adminDraftsIntro">
              <span>Unscheduled drafts</span>
              <p>Drag onto a day to schedule.</p>
            </div>
            {rows.filter((question) => question.status === "draft").slice(0, 3).map((question) => (
              <button key={`draft-${question.id}`} onClick={() => applyQuestion(question)}>
                <span><CategoryDot category={question.category} /> {displayCategory(question.category)}</span>
                <strong>{question.prompt}</strong>
              </button>
            ))}
          </aside>
        </div>
      </>
    );
  }

  function renderLibrary() {
    const baseLibraryRows = devAdminPreview && questions.length === 0 ? sourceOrderedLibraryRows(rows) : rows;
    const libraryRows = baseLibraryRows.filter((question) => {
      if (libraryFilter === "All") return true;
      if (libraryFilter === "Used") return question.status === "closed";
      return question.status === libraryFilter.toLowerCase();
    });
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Question library</h1>
            <p>{baseLibraryRows.length} questions · write, edit, and categorize.</p>
          </div>
          <button className="adminBlueButton" onClick={startNewQuestion}>+ New question</button>
        </div>
        <div className="adminFilterPills">
          {(["All", "Live", "Scheduled", "Used", "Draft"] as LibraryFilter[]).map((label) => (
            <button
              className={libraryFilter === label ? "active" : ""}
              key={label}
              onClick={() => setLibraryFilter(label)}
            >
              {label}
            </button>
          ))}
        </div>
        <section className="adminLibraryTable">
          <div className="adminLibraryHeader">
            <span>Question</span>
            <span>Category</span>
            <span>Status</span>
            <span>World</span>
          </div>
          {libraryRows.map((question, index) => (
            <button
              className={question.id === activeQuestionId ? "active" : ""}
              key={question.id}
              onClick={() => applyQuestion(question)}
            >
              <span>{question.prompt}</span>
              <span><CategoryDot category={question.category} /> {displayCategory(question.category)}</span>
              <em data-status={question.status}>{displayStatus(question.status)}</em>
              <span>
                {questionWorldPct(question, overview) ??
                  (devAdminPreview ? previewLibraryWorldPct(question) ?? (question.status === "closed" || question.status === "live" ? `${68 - index * 3}%` : "--") : "--")}
              </span>
            </button>
          ))}
        </section>
        {questionEditorOpen ? renderQuestionEditor() : null}
      </>
    );
  }

  function renderAnalytics() {
    const metrics = overview?.metrics;
    const bars = normalizedBars(overview?.dailyActivity.map((item) => item.value));
    const categoryRows: Array<[string, number]> = overview?.categoryRows.length
      ? overview.categoryRows.map((row) => [displayCategory(row.category), row.value] as [string, number])
      : devAdminPreview ? [
        ["Technology", 92],
        ["Society", 88],
        ["Culture", 81],
        ["Philosophy", 78],
        ["Money", 74],
        ["Science", 71],
        ["Health", 64],
        ["Ethics", 58],
      ] : [];
    const retentionRows: Array<[string, number]> = overview?.retentionRows.length
      ? overview.retentionRows.map((row) => [row.label, row.value] as [string, number])
      : devAdminPreview ? [["D1", 62], ["D3", 48], ["D7", 38], ["D14", 30], ["D30", 24]] : [];
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Analytics</h1>
            <p>Last 30 days · engagement, retention and audience.</p>
          </div>
          <div className="adminSegment">
            <button className="active">30D</button>
            <button>90D</button>
            <button>All</button>
          </div>
        </div>
        <div className="adminMetricGrid adminAnalyticsMetrics">
          <MetricCard label="Avg daily active" value={formatCount(metrics?.activeUsers, devAdminPreview ? "1,540" : "0")} detail={devAdminPreview ? "+18% MoM" : `${formatCount(metrics?.totalUsers)} total readers`} />
          <MetricCard label="D7 retention" value={formatPercentValue(retentionRows.find(([label]) => label === "D7")?.[1], devAdminPreview ? "38%" : "0%")} detail={devAdminPreview ? "+2.1 pts" : "Streak proxy"} />
          <MetricCard label="Avg streak" value={metrics ? `${metrics.avgStreak.toFixed(1)} days` : "0.0 days"} detail={`${formatCount(metrics?.activeStreaks, devAdminPreview ? "1,203" : "0")} active streaks`} />
          <MetricCard
            label={overview ? "Push tokens" : "Party rounds"}
            value={formatCount(metrics?.notificationTokens, devAdminPreview ? "612" : "0")}
            detail={overview ? `${formatCount(metrics?.waitlistSignups, "0")} waitlist signups` : devAdminPreview ? "+44% MoM" : "0 waitlist signups"}
          />
        </div>
        <section className="adminDesignPanel">
          <PanelHeader label="Daily active users" meta={overview ? `${formatCount(metrics?.activeUsers)} current active` : devAdminPreview ? "820 -> 1,892" : "No activity loaded"} />
          <div className="adminBarChart">
            {bars.map((height, index) => (
              <span key={index} style={{ height: `${height}%` }} />
            ))}
            {bars.length === 0 ? <em>No activity yet.</em> : null}
          </div>
        </section>
        <div className="adminTwoCols">
          <section className="adminDesignPanel">
            <PanelHeader label="Engagement by category" />
            <ProgressRows
              rows={categoryRows}
              colorForRow={(label) => categoryColors[label.toUpperCase()] ?? "#3E5BA0"}
            />
          </section>
          <section className="adminDesignPanel">
            <PanelHeader label="Retention curve" />
            <div className="adminRetentionBars">
              {retentionRows.map(([label, value]) => (
                <div key={label}>
                  <strong>{value}%</strong>
                  <span style={{ height: `${Number(value) * 1.9}px` }} />
                  <em>{label}</em>
                </div>
              ))}
            </div>
          </section>
        </div>
      </>
    );
  }

  function renderResults() {
    const accuracyRows = accuracyBucketRows(focusedResult);
    const ageRows: Array<[string, number]> = overview?.audience.age.length
      ? overview.audience.age.map((row) => [row.label, row.value] as [string, number])
      : devAdminPreview ? [["18-24", 75], ["25-34", 70], ["35-44", 66], ["45-54", 59], ["55+", 52]] : [];
    const genderRows: Array<[string, number]> = overview?.audience.gender.length
      ? overview.audience.gender.map((row) => [row.label, row.value] as [string, number])
      : devAdminPreview ? [["Women", 64], ["Men", 73], ["Non-binary", 70]] : [];
    const countryRows: Array<[string, number]> = overview?.audience.country.length
      ? overview.audience.country.map((row) => [row.label, row.value] as [string, number])
      : devAdminPreview ? [["United States", 69], ["United Kingd...", 66], ["Canada", 67], ["Australia", 71], ["Germany", 63]] : [];
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Question results</h1>
            <p>How the world answered · how well users predicted it.</p>
          </div>
        </div>
        <section className="adminResultsHero">
          <div className="adminKicker">
            <CategoryDot category={resultsQuestion.category} /> {displayCategory(resultsQuestion.category)} · {shortDate(resultsQuestion.dailyKey || (focusedResult?.closedAt ?? null))} · {displayStatus(resultsQuestion.status)}
          </div>
          <h2 className="adminSerif">{resultsQuestion.prompt}</h2>
          <div className="adminResultsGrid">
            <ResultDonut {...resultDonut} />
            <div>
              <PanelHeader label="How well users predicted (Read Accuracy)" />
              <div className="adminAccuracyBars">
                {accuracyRows.map(([label, value]) => (
                  <div key={label}>
                    <strong>{value}%</strong>
                    <span style={{ height: `${Number(value) * 2.1}px` }} />
                    <em>{label}</em>
                  </div>
                ))}
              </div>
              <div className="adminResultStats">
                <span>Avg guess <strong>{focusedResult?.avgPredictedShare ?? "--"}%</strong></span>
                <span>Median Read Score <strong>{focusedResult?.medianReadAccuracy ?? "--"}/100</strong></span>
                <span>Nailed it (90+) <strong>{focusedResult?.highAccuracyPct ?? "--"}%</strong></span>
              </div>
            </div>
          </div>
        </section>
        <div className="adminThreeCols">
          <Breakdown title="Yes % by age" rows={ageRows} />
          <Breakdown title="Yes % by gender" rows={genderRows} />
          <Breakdown title="Yes % by country" rows={countryRows} />
        </div>
      </>
    );
  }

  function renderNotifications() {
    const metrics = overview?.metrics;
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Notifications</h1>
            <p>Daily reminders and broadcast messages.</p>
          </div>
        </div>
        <div className="adminNotifyGrid">
          <section className="adminDesignPanel">
            <PanelHeader label="New broadcast" />
            <input value={broadcastTitle} onChange={(event) => setBroadcastTitle(event.target.value)} />
            <textarea value={broadcastBody} onChange={(event) => setBroadcastBody(event.target.value)} />
            <div className="adminKicker">Audience</div>
            <div className="adminFilterPills">
              {broadcastAudiences.map((audience) => (
                <button
                  className={broadcastAudience === audience.id ? "active" : ""}
                  key={audience.id}
                  onClick={() => setBroadcastAudience(audience.id)}
                >
                  {audience.label} · {audienceCount(audience.id, metrics)}
                </button>
              ))}
            </div>
            <div className="adminNotifyActions">
              <span>{busyAction === "sendBroadcastNotification" ? "Sending" : "Send now"}</span>
              <button
                className="adminBlueButton"
                disabled={Boolean(busyAction)}
                onClick={() => runCallable("sendBroadcastNotification", {
                  title: broadcastTitle,
                  body: broadcastBody,
                  audience: broadcastAudience,
                  route: broadcastRoute,
                })}
              >
                Send broadcast
              </button>
            </div>
          </section>
          <aside>
            <div className="adminReminderCard">
              <div>
                <strong>Daily reminder</strong>
                <span>9:00 AM · user local time</span>
              </div>
              <span className="adminToggle active" />
            </div>
            <div className="adminLockPreview">
              <div className="adminKicker">Lock-screen preview</div>
              <div>
                <span>r.</span>
                <p><strong>Read the World</strong><br />Today&apos;s question is live 🌍 Can you read the world today?</p>
              </div>
            </div>
          </aside>
        </div>
        <section className="adminLibraryTable adminNotificationTable">
          <div className="adminLibraryHeader">
            <span>Message</span>
            <span>Sent</span>
            <span>Delivered</span>
            <span>Open rate</span>
          </div>
          <div className="adminTableRow">
            <span>No broadcast history loaded yet.</span>
            <span>--</span>
            <span>--</span>
            <span>--</span>
          </div>
        </section>
      </>
    );
  }

  function renderSettings() {
    const flags = featureFlags.length > 0 ? featureFlags : devAdminPreview ? sampleFeatureFlags : [];
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Settings</h1>
            <p>Feature flags and app configuration.</p>
          </div>
        </div>
        <section className="adminSettingsList">
          <PanelHeader label="Feature flags" />
          {flags.map((flag) => (
            <div className="adminSettingRow" key={flag.key}>
              <div>
                <strong>{flag.label}</strong>
                <span>{flag.description}</span>
              </div>
              <button
                aria-label={`Turn ${flag.label} ${flag.enabled ? "off" : "on"}`}
                className={`adminToggle ${flag.enabled ? "active" : ""}`}
                disabled={Boolean(busyAction)}
                onClick={() => runCallable("setAdminFeatureFlag", {
                  key: flag.key,
                  enabled: !flag.enabled,
                })}
                type="button"
              />
            </div>
          ))}
          {flags.length === 0 ? <p>No feature flags loaded yet.</p> : null}
        </section>
        <section className="adminSettingsList">
          <PanelHeader label="Timing" />
          <div className="adminSettingRow">
            <div><strong>New question drops</strong><span>When today&apos;s question goes live</span></div>
            <button>00:00 local</button>
          </div>
          <div className="adminSettingRow">
            <div><strong>Results reveal</strong><span>When the world&apos;s answer unlocks</span></div>
            <button>Next day 00:00</button>
          </div>
        </section>
        <section className="adminSettingsList adminCategoryPanel">
          <PanelHeader label="Categories" />
          <div className="adminCategoryTags">
            {Object.keys(categoryColors).map((cat) => (
              <span key={cat}><CategoryDot category={cat} /> {displayCategory(cat)}</span>
            ))}
            <button className="adminGhostButton">+ Add category</button>
          </div>
        </section>
        {user ? (
          <section className="adminSettingsList">
            <PanelHeader label="Admin session" />
            <div className="adminSettingRow">
              <div><strong>{user.email ?? user.uid}</strong><span>Firebase admin claim session</span></div>
              <button onClick={() => refreshAdminClaim(user)} disabled={checkingClaims}>
                {checkingClaims ? "Checking..." : "Refresh claim"}
              </button>
            </div>
            <div className="adminSettingRow">
              <div><strong>Sign out</strong><span>Leave the protected admin surface</span></div>
              <button onClick={() => auth && signOut(auth)}>Sign out</button>
            </div>
          </section>
        ) : null}
      </>
    );
  }

  function renderQuestionEditor() {
    return (
      <section className="adminEditor">
        <div className="adminViewHead compact">
          <div>
            <div className="adminKicker">Question editor</div>
            <h2 className="adminSerif">{activeQuestionId ? "Edit question" : "New question"}</h2>
          </div>
          <button onClick={resetQuestionForm}>Clear</button>
        </div>
        <div className="adminEditorGrid">
          <label>
            Question ID
            <input value={questionId} onChange={(event) => setQuestionId(event.target.value)} />
          </label>
          <label>
            Category
            <input value={category} onChange={(event) => setCategory(event.target.value)} />
          </label>
          <label>
            Daily key
            <input value={dailyKey} onChange={(event) => setDailyKey(event.target.value)} />
          </label>
          <label>
            Status
            <select value={status} onChange={(event) => setStatus(event.target.value)}>
              <option value="draft">Draft</option>
              <option value="scheduled">Scheduled</option>
              <option value="live">Live</option>
              <option value="closed">Closed</option>
            </select>
          </label>
          <label>
            Publish at
            <input value={publishAt} onChange={(event) => setPublishAt(event.target.value)} />
          </label>
          <label>
            Close at
            <input value={closeAt} onChange={(event) => setCloseAt(event.target.value)} />
          </label>
          <label className="wide">
            Prompt
            <textarea value={prompt} onChange={(event) => setPrompt(event.target.value)} />
          </label>
          <div className="wide optionEditor">
            <div className="optionEditorTop">
              <span>Options</span>
              <button
                type="button"
                onClick={() => setOptions((current) => [...current, { id: "", label: "" }])}
              >
                Add option
              </button>
            </div>
            {options.map((option, index) => (
              <div className="optionRow" key={index}>
                <input
                  aria-label={`Option ${index + 1} ID`}
                  value={option.id}
                  onChange={(event) => updateOption(index, "id", event.target.value)}
                />
                <input
                  aria-label={`Option ${index + 1} label`}
                  value={option.label}
                  onChange={(event) => updateOption(index, "label", event.target.value)}
                />
                <button
                  type="button"
                  disabled={options.length <= 2}
                  onClick={() =>
                    setOptions((current) => current.filter((_, optionIndex) => optionIndex !== index))
                  }
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        </div>
        <div className="adminActions">
          <button
            className="adminBlueButton"
            disabled={Boolean(busyAction)}
            onClick={() => runCallable("upsertQuestion", questionPayload("draft"))}
          >
            <Save size={17} /> {busyAction === "upsertQuestion" ? "Saving..." : "Save draft"}
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("upsertQuestion", questionPayload("scheduled"))}>
            <Save size={17} /> Schedule
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("upsertQuestion", questionPayload("live"))}>
            <Eye size={17} /> Make live
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("seedInitialQuestions")}>
            <UploadCloud size={17} /> Seed initial set
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("closeQuestionNow", { questionId })}>
            <CheckCircle2 size={17} /> Close now
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("recomputeQuestion", { questionId })}>
            Recompute
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("recomputeLeaderboardsNow")}>
            Recompute leaderboard
          </button>
        </div>
      </section>
    );
  }

  return (
    <main className="adminApp" aria-busy={loadingOverview}>
      <aside className="adminSidebar">
        <div className="adminBrandRow">
          <div className="adminBrand">read<span>.</span></div>
          <span>Admin</span>
        </div>
        <nav>
          {navItems.map((item) => (
            <button
              className={activeView === item.id ? "active" : ""}
              key={item.id}
              onClick={() => setActiveView(item.id)}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </nav>
        <div className="adminOwner">
          <span>{displayInitial}</span>
          <div>
            <strong>{displayName}</strong>
            <em>Owner</em>
          </div>
        </div>
      </aside>
      <section className="adminWorkspace">
        {renderContent()}
        {activeView === "analytics" && adminUnlocked ? (
          <WaitlistPanel
            entries={waitlist}
            loading={loadingWaitlist}
            onExport={exportWaitlistCsv}
            onRefresh={loadWaitlist}
          />
        ) : null}
        {message ? <pre>{message}</pre> : null}
      </section>
    </main>
  );
}

function MetricCard({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <section className="adminMetricCard">
      <span>{label}</span>
      <strong>{value}</strong>
      <em>{detail}</em>
    </section>
  );
}

type DonutProps = {
  value: number;
  label: string;
  segments: Array<{ label: string; value: number }>;
};

function ResultDonut({ value, label, segments }: DonutProps) {
  const safeValue = clampPercent(value);
  const first = segments[0] ?? { label: "Yes", value: safeValue };
  const second = segments[1] ?? { label: "--", value: 0 };
  return (
    <div className="adminDonut" aria-label={`${safeValue} percent ${label.toLowerCase()}`}>
      <div style={{ background: `conic-gradient(var(--clay) 0 ${safeValue}%, #ded8ca ${safeValue}% 100%)` }}>
        <div className="adminDonutInner">
          <strong>{safeValue}%</strong>
          <span>{label}</span>
        </div>
      </div>
      <p><span /> {first.label} {clampPercent(first.value)} <i /> {second.label} {clampPercent(second.value)}</p>
    </div>
  );
}

function Sparkline({ values, preview = false }: { values: number[]; preview?: boolean }) {
  const pathValues = values.length >= 2
    ? values
    : preview ? [40, 220, 520, 760, 980, 1140, 1280, 1410, 1520, 1600, 1640] : [];
  if (pathValues.length < 2) {
    return (
      <div className="adminLineChart" aria-hidden="true">
        <svg viewBox="0 0 520 120" preserveAspectRatio="none" />
      </div>
    );
  }
  const max = values.length >= 2 ? Math.max(...pathValues, 1) : 1700;
  const points = pathValues.map((value, index) => {
    const x = pathValues.length === 1 ? 0 : (index / (pathValues.length - 1)) * 520;
    const y = 116 - (value / max) * 110;
    return [Math.round(x * 10) / 10, Math.round(y * 10) / 10] as const;
  });
  const line = points.map(([x, y], index) => `${index === 0 ? "M" : "L"}${x} ${y}`).join(" ");
  const fill = `M0 116 ${points.map(([x, y]) => `L${x} ${y}`).join(" ")} L520 116 Z`;
  return (
    <div className="adminLineChart" aria-hidden="true">
      <svg viewBox="0 0 520 120" preserveAspectRatio="none">
        <path d={line} />
        <path d={fill} />
      </svg>
    </div>
  );
}

function PanelHeader({ label, meta }: { label: string; meta?: string }) {
  return (
    <div className="adminPanelHeader">
      <span>{label}</span>
      {meta ? <em>{meta}</em> : null}
    </div>
  );
}

function ProgressRows({
  rows,
  colorForRow,
}: {
  rows: Array<[string, number]>;
  colorForRow?: (label: string, index: number) => string;
}) {
  return (
    <div className="adminProgressRows">
      {rows.map(([label, value], index) => (
        <div key={label}>
          <span>{label}</span>
          <div><i style={{ width: `${value}%`, background: colorForRow?.(label, index) ?? "var(--clay)" }} /></div>
          <em>{value}</em>
        </div>
      ))}
    </div>
  );
}

function Breakdown({ title, rows }: { title: string; rows: Array<[string, number]> }) {
  return (
    <section className="adminDesignPanel">
      <PanelHeader label={title} />
      <ProgressRows rows={rows} />
    </section>
  );
}

function CategoryDot({ category }: { category: string }) {
  return (
    <i
      className="adminCategoryDot"
      style={{ background: categoryColors[category.toUpperCase()] ?? "#8A8475" }}
    />
  );
}

function WaitlistPanel({
  entries,
  loading,
  onExport,
  onRefresh,
}: {
  entries: WaitlistEntry[];
  loading: boolean;
  onExport: () => void;
  onRefresh: () => void;
}) {
  return (
    <section className="adminWaitlist">
      <div className="adminWaitlistTop">
        <div>
          <div className="adminKicker">Waitlist</div>
          <h2 className="adminSerif">{loading ? "Loading..." : `${entries.length} recent signups`}</h2>
        </div>
        <div>
          <button type="button" onClick={onRefresh} disabled={loading}>
            <RefreshCw size={16} /> Refresh
          </button>
          <button type="button" onClick={onExport} disabled={entries.length === 0}>
            <Download size={16} /> Export CSV
          </button>
        </div>
      </div>
      <div className="waitlistTable" role="table" aria-label="Recent waitlist signups">
        <div role="row" className="waitlistHeader">
          <span>Email</span>
          <span>Source</span>
          <span>Read</span>
          <span>Latest</span>
        </div>
        {entries.map((entry) => (
          <div role="row" key={entry.id}>
            <span>{entry.email}</span>
            <span>{entry.source || "landing"}</span>
            <span>{entry.answer ? `${entry.answer} · ${entry.predictedShare ?? "--"}%` : "No read captured"}</span>
            <span>{shortDate(entry.latestAt)}</span>
          </div>
        ))}
        {!loading && entries.length === 0 ? <p>No waitlist signups loaded yet.</p> : null}
      </div>
    </section>
  );
}

function questionForDay(rows: AdminQuestion[], day: number) {
  return rows.find((question) => {
    const match = /-(\d{2})$/.exec(question.dailyKey);
    return match ? Number(match[1]) === day : false;
  });
}

function calendarPreviewQuestions(rows: AdminQuestion[]) {
  if (rows.length === 0) return [];
  const scheduledRows = rows.filter((question) => question.dailyKey);
  const generated = Array.from({ length: 27 }, (_, index) => {
    const day = index + 1;
    const existing = questionForDay(rows, day);
    if (existing) return existing;
    const base = scheduledRows[index % scheduledRows.length] ?? rows[0];
    return {
      ...base,
      id: `preview-2026-06-${String(day).padStart(2, "0")}`,
      dailyKey: `2026-06-${String(day).padStart(2, "0")}`,
      status: day === 25 ? "live" : day > 25 ? "scheduled" : "closed",
    };
  });
  return [...generated, ...rows.filter((question) => !question.dailyKey)];
}

function sourceOrderedLibraryRows(rows: AdminQuestion[]) {
  const sourceOrder = [
    "2026-06-25-philosophy-death-date",
    "2026-06-26-culture-phones-dinner",
    "2026-06-27-society-billionaires",
    "2026-06-01-technology-ai-labels",
    "2026-06-02-money-happiness",
    "2026-06-03-culture-hot-dog",
    "2026-06-04-society-social-media",
    "2026-06-05-philosophy-free-will",
    "draft-ethics-lie-feelings",
    "draft-science-mars",
    "draft-society-remote-office",
    "draft-philosophy-luck-hard-work",
  ];
  return sourceOrder
    .map((id) => rows.find((question) => question.id === id))
    .filter((question): question is AdminQuestion => Boolean(question));
}

function questionFromSnapshot(snapshot: QueryDocumentSnapshot<DocumentData>): AdminQuestion {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    prompt: stringValue(data.prompt),
    category: stringValue(data.category),
    status: stringValue(data.status) || "draft",
    dailyKey: stringValue(data.dailyKey),
    publishAt: dateValue(data.publishAt),
    closeAt: dateValue(data.closeAt),
    options: optionValues(data.options),
  };
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : "";
}

function dateValue(value: unknown) {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  return "";
}

function optionValues(value: unknown): QuestionOption[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((option) => {
      if (!option || typeof option !== "object") return null;
      const record = option as Record<string, unknown>;
      return {
        id: stringValue(record.id),
        label: stringValue(record.label),
      };
    })
    .filter((option): option is QuestionOption => Boolean(option?.id && option.label));
}

function adminOverviewFromData(value: unknown): AdminOverview {
  const record = objectValue(value);
  const audience = objectValue(record.audience);
  return {
    generatedAt: stringValue(record.generatedAt),
    metrics: metricSummaryFromData(record.metrics),
    questions: arrayValue(record.questions).map(adminQuestionFromData),
    results: arrayValue(record.results).map(adminResultFromData),
    focusResult: record.focusResult == null ? null : adminResultFromData(record.focusResult),
    liveCounters: liveCountersFromData(record.liveCounters),
    dailyActivity: arrayValue(record.dailyActivity).map(labelValueFromData),
    categoryRows: arrayValue(record.categoryRows).map(categoryRowFromData),
    retentionRows: arrayValue(record.retentionRows).map(labelValueFromData),
    audience: {
      age: arrayValue(audience.age).map(bucketRowFromData),
      gender: arrayValue(audience.gender).map(bucketRowFromData),
      country: arrayValue(audience.country).map(bucketRowFromData),
    },
  };
}

function adminQuestionFromData(value: unknown): AdminQuestion {
  const record = objectValue(value);
  return {
    id: stringValue(record.id),
    prompt: stringValue(record.prompt),
    category: stringValue(record.category),
    status: stringValue(record.status) || "draft",
    dailyKey: stringValue(record.dailyKey),
    publishAt: stringValue(record.publishAt),
    closeAt: stringValue(record.closeAt),
    options: optionValues(record.options),
  };
}

function adminResultFromData(value: unknown): AdminResultSummary {
  const record = objectValue(value);
  return {
    questionId: stringValue(record.questionId),
    prompt: stringValue(record.prompt),
    category: stringValue(record.category),
    dailyKey: stringValue(record.dailyKey),
    status: stringValue(record.status) || "closed",
    options: optionValues(record.options),
    totalAnswers: numberValue(record.totalAnswers),
    optionCounts: numberRecord(record.optionCounts),
    optionPcts: numberRecord(record.optionPcts),
    countedTowardScore: record.countedTowardScore === true,
    closedAt: nullableString(record.closedAt),
    avgPredictedShare: nullableNumber(record.avgPredictedShare),
    medianReadAccuracy: nullableNumber(record.medianReadAccuracy),
    highAccuracyPct: nullableNumber(record.highAccuracyPct),
    accuracyBuckets: numberRecord(record.accuracyBuckets),
  };
}

function metricSummaryFromData(value: unknown): AdminMetricSummary {
  const record = objectValue(value);
  return {
    totalUsers: numberValue(record.totalUsers),
    activeUsers: numberValue(record.activeUsers),
    newUsers7d: numberValue(record.newUsers7d),
    waitlistSignups: numberValue(record.waitlistSignups),
    notificationTokens: numberValue(record.notificationTokens),
    leaderboardRows: numberValue(record.leaderboardRows),
    answersToday: numberValue(record.answersToday),
    predictionsLocked: numberValue(record.predictionsLocked),
    avgStreak: numberValue(record.avgStreak),
    activeStreaks: numberValue(record.activeStreaks),
  };
}

function liveCountersFromData(value: unknown): AdminOverview["liveCounters"] {
  if (value == null) return null;
  const record = objectValue(value);
  return {
    questionId: stringValue(record.questionId),
    totalAnswers: numberValue(record.totalAnswers),
    optionCounts: numberRecord(record.optionCounts),
    optionPcts: numberRecord(record.optionPcts),
  };
}

function labelValueFromData(value: unknown) {
  const record = objectValue(value);
  return {
    label: stringValue(record.label),
    value: numberValue(record.value),
  };
}

function categoryRowFromData(value: unknown) {
  const record = objectValue(value);
  return {
    category: stringValue(record.category),
    value: numberValue(record.value),
    answers: numberValue(record.answers),
  };
}

function bucketRowFromData(value: unknown) {
  const record = objectValue(value);
  return {
    label: stringValue(record.label),
    value: numberValue(record.value),
    count: numberValue(record.count),
  };
}

function featureFlagFromData(value: unknown): AdminFeatureFlag {
  const record = objectValue(value);
  return {
    key: stringValue(record.key),
    label: stringValue(record.label),
    description: stringValue(record.description),
    enabled: record.enabled === true,
  };
}

function waitlistEntryFromData(value: unknown): WaitlistEntry {
  const record = value && typeof value === "object" ? value as Record<string, unknown> : {};
  return {
    id: stringValue(record.id),
    email: stringValue(record.email),
    source: stringValue(record.source),
    answer: nullableString(record.answer),
    predictedShare: nullableNumber(record.predictedShare),
    signupCount: nullableNumber(record.signupCount) ?? 1,
    uid: nullableString(record.uid),
    createdAt: nullableString(record.createdAt),
    latestAt: nullableString(record.latestAt),
  };
}

function resultAsQuestion(result: AdminResultSummary): AdminQuestion {
  return {
    id: result.questionId,
    prompt: result.prompt,
    category: result.category,
    status: result.status,
    dailyKey: result.dailyKey,
    publishAt: "",
    closeAt: result.closedAt ?? "",
    options: result.options,
  };
}

function resultForQuestion(questionId: string, overview: AdminOverview | null) {
  return overview?.results.find((result) => result.questionId === questionId) ?? null;
}

function questionWorldPct(question: AdminQuestion, overview: AdminOverview | null) {
  const result = resultForQuestion(question.id, overview);
  const source = result?.optionPcts ??
    (overview?.liveCounters?.questionId === question.id ? overview.liveCounters.optionPcts : null);
  if (!source) return null;
  const firstOptionId = question.options[0]?.id ?? Object.keys(source)[0];
  if (!firstOptionId) return null;
  const value = source[firstOptionId];
  return Number.isFinite(value) ? `${clampPercent(value)}%` : null;
}

function previewLibraryWorldPct(question: AdminQuestion) {
  const values: Record<string, string> = {
    "2026-06-25-philosophy-death-date": "68%",
    "2026-06-01-technology-ai-labels": "84%",
    "2026-06-02-money-happiness": "57%",
    "2026-06-03-culture-hot-dog": "39%",
    "2026-06-04-society-social-media": "62%",
    "2026-06-05-philosophy-free-will": "71%",
  };
  return values[question.id] ?? null;
}

function donutForQuestion(question: AdminQuestion, overview: AdminOverview | null): DonutProps {
  const result = resultForQuestion(question.id, overview);
  if (result) return donutForResult(result);
  const pcts = overview?.liveCounters?.questionId === question.id ? overview.liveCounters.optionPcts : {};
  return donutFromOptions(question.options, pcts);
}

function donutForResult(result: AdminResultSummary): DonutProps {
  return donutFromOptions(result.options, result.optionPcts);
}

function donutFromOptions(options: QuestionOption[], pcts: Record<string, number>): DonutProps {
  const segments = options.length > 0
    ? options.map((option) => ({
      label: option.label,
      value: numberValue(pcts[option.id]),
    })).filter((segment) => segment.value > 0)
    : Object.entries(pcts).map(([label, value]) => ({
      label: displayCategory(label),
      value: numberValue(value),
    }));
  const displaySegments = segments.length > 0
    ? segments
    : options.slice(0, 2).map((option) => ({ label: option.label, value: 0 }));
  const first = displaySegments[0] ?? { label: "No data", value: 0 };
  return {
    value: clampPercent(first.value),
    label: segments.length > 0 ? `Said ${first.label.toLowerCase()}` : "No result yet",
    segments: displaySegments.slice(0, 2),
  };
}

function accuracyBucketRows(result: AdminResultSummary | null): Array<[string, number]> {
  const fallback: Array<[string, number]> = [["0-20", 4], ["21-40", 9], ["41-60", 21], ["61-80", 38], ["81-100", 28]];
  if (!result) return fallback.map(([label]) => [label, 0]);
  const rows = fallback.map(([label]) => [label, clampPercent(result.accuracyBuckets[label] ?? 0)] as [string, number]);
  return rows.some(([, value]) => value > 0) ? rows : fallback.map(([label]) => [label, 0]);
}

function normalizedBars(values: number[] | undefined): number[] {
  if (!values || values.length === 0) return [];
  const max = Math.max(...values, 1);
  return values.map((value) => Math.max(8, Math.round((value / max) * 100)));
}

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function numberValue(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function numberRecord(value: unknown): Record<string, number> {
  const record = objectValue(value);
  return Object.fromEntries(
    Object.entries(record)
      .map(([key, recordValue]) => [key, numberValue(recordValue)] as const)
      .filter(([, recordValue]) => Number.isFinite(recordValue)),
  );
}

function clampPercent(value: number) {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function formatCount(value: number | null | undefined, fallback = "0") {
  if (value == null || !Number.isFinite(value)) return fallback;
  return new Intl.NumberFormat("en").format(value);
}

function formatPercentValue(value: number | null | undefined, fallback: string) {
  if (value == null || !Number.isFinite(value)) return fallback;
  return `${clampPercent(value)}%`;
}

function formatPercentOf(part: number | null | undefined, total: number | null | undefined, fallback: string) {
  if (part == null || total == null || total <= 0) return fallback;
  return `${clampPercent((part / total) * 100)}%`;
}

function audienceCount(audience: BroadcastAudience, metrics: AdminMetricSummary | undefined) {
  if (audience === "all") return formatCount(metrics?.totalUsers);
  if (audience === "streak_at_risk") return formatCount(metrics?.activeStreaks);
  return formatCount(metrics?.notificationTokens);
}

function nullableString(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function nullableNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function csvCell(value: string) {
  return `"${value.replaceAll("\"", "\"\"")}"`;
}

function shortDate(value: string | null) {
  if (!value) return "--";
  const dailyKey = parseDailyKey(value);
  if (dailyKey) {
    return new Intl.DateTimeFormat("en", {
      month: "short",
      day: "numeric",
      year: "numeric",
      timeZone: "UTC",
    }).format(dailyKey);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "--";
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function longDate(value: string) {
  const dailyKey = parseDailyKey(value);
  if (!dailyKey) return null;
  return new Intl.DateTimeFormat("en", {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(dailyKey);
}

function parseDailyKey(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
}

function timeUntil(value: string) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const diff = date.getTime() - Date.now();
  if (diff <= 0) return "Ready";
  const hours = Math.floor(diff / (60 * 60 * 1000));
  const minutes = Math.floor((diff % (60 * 60 * 1000)) / (60 * 1000));
  return `${hours}h ${minutes}m`;
}

function validatePayload(name: string, payload: Record<string, unknown>) {
  if (name !== "upsertQuestion") {
    if ((name === "closeQuestionNow" || name === "recomputeQuestion") && !stringValue(payload.questionId)) {
      return "Choose a question before running this action.";
    }
    return "";
  }
  if (!stringValue(payload.questionId)) return "Question ID is required.";
  if (!stringValue(payload.prompt)) return "Prompt is required.";
  if (!stringValue(payload.category)) return "Category is required.";
  if (!stringValue(payload.dailyKey)) return "Daily key is required.";
  if (!Array.isArray(payload.options) || payload.options.length < 2) {
    return "At least two complete options are required.";
  }
  return "";
}

function displayCategory(value: string) {
  const lower = value.toLowerCase();
  return lower.charAt(0).toUpperCase() + lower.slice(1);
}

function displayStatus(value: string) {
  if (value === "closed") return "Used";
  return displayCategory(value || "draft");
}
