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
  doc,
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
  CircleDot,
  ClipboardList,
  Download,
  Globe2,
  Library,
  RefreshCw,
  Save,
  SlidersHorizontal,
  Users,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { activateClientAppCheck } from "@/lib/appCheck";
import {
  QuestionBankView,
  RoomsOverviewView,
  WorldCurationView,
  useBankQuestions,
  type BankQuestion,
} from "@/components/AdminV2";

type AdminState = "missing-config" | "signed-out" | "checking" | "authorized" | "unauthorized";
export type AdminView = "bank" | "world" | "rooms" | "today" | "schedule" | "library" | "analytics" | "results" | "notifications" | "settings";
type BroadcastAudience = "all" | "streak_at_risk" | "lapsed_7d";
type LibraryFilter = "All" | "Active" | "Retired" | "Used" | "Work-safe" | "Normal" | "After Dark";
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
  dailyCompletersToday: number;
  returningCompletersToday: number;
  returningCompleterPctToday: number;
  avgStreak: number;
  activeStreaks: number;
};
type AdminDailyCompletionRow = {
  label: string;
  completers: number;
  returningCompleters: number;
  newCompleters: number;
  returningPct: number;
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
  completionRows: AdminDailyCompletionRow[];
  categoryRows: Array<{ category: string; value: number; answers: number }>;
  retentionRows: Array<{ label: string; value: number }>;
  audience: {
    age: Array<{ label: string; value: number; count: number }>;
    gender: Array<{ label: string; value: number; count: number }>;
    country: Array<{ label: string; value: number; count: number }>;
  };
};

type AdminWorldDayQuestion = {
  qid: string;
  prompt: string;
  optA: string;
  optB: string;
  tag: string;
  tier: string;
  threshold: number | null;
  pulled: boolean;
};

type AdminWorldDay = {
  dailyKey: string;
  status: string;
  answerCount: number;
  answerCounts: Record<string, number>;
  questions: AdminWorldDayQuestion[];
};
type WorldSchedulePick = {
  qid: string;
  prompt: string;
  optA: string;
  optB: string;
  tag: string;
  tier: string;
  threshold: number;
};

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const allowedAdminEmail = "mike@readtheworld.today";

const navItems: Array<{ id: AdminView; label: string; icon: ReactNode }> = [
  { id: "bank", label: "Question bank", icon: <Library size={15} /> },
  { id: "world", label: "The World", icon: <Globe2 size={15} /> },
  { id: "rooms", label: "Rooms", icon: <Users size={15} /> },
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

const adminCategories = Object.keys(categoryColors);
const bankShapes = ["TASTE", "CONFESS", "MIRROR", "GREY", "TRADE", "NORM", "HABIT", "BELIEF"];
const adminTierLabels: Record<BankQuestion["tier"] | string, string> = {
  "work-safe": "Work-safe",
  normal: "Normal",
  mature: "After Dark",
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
  const [prompt, setPrompt] = useState("");
  const [category, setCategory] = useState("");
  const [bankTier, setBankTier] = useState<BankQuestion["tier"]>("normal");
  const [bankShape, setBankShape] = useState("TASTE");
  const [bankActive, setBankActive] = useState(true);
  const [options, setOptions] = useState<QuestionOption[]>([
    { id: "yes", label: "Yes" },
    { id: "no", label: "No" },
  ]);
  const [waitlist, setWaitlist] = useState<WaitlistEntry[]>([]);
  const [loadingWaitlist, setLoadingWaitlist] = useState(false);
  const [overview, setOverview] = useState<AdminOverview | null>(null);
  const [worldCurrentDailyKey, setWorldCurrentDailyKey] = useState("");
  const [worldDay, setWorldDay] = useState<AdminWorldDay | null>(null);
  const [scheduleWorldDays, setScheduleWorldDays] = useState<AdminWorldDay[]>([]);
  const [selectedScheduleDailyKey, setSelectedScheduleDailyKey] = useState(defaultWorldScheduleKey());
  const [scheduleMonthKey, setScheduleMonthKey] = useState(defaultWorldScheduleKey().slice(0, 7));
  const [scheduleDrafts, setScheduleDrafts] = useState<Record<string, WorldSchedulePick[]>>({});
  const [scheduleQuestionSearch, setScheduleQuestionSearch] = useState("");
  const [scheduleQuestionPage, setScheduleQuestionPage] = useState(0);
  const [loadingOverview, setLoadingOverview] = useState(false);
  const [featureFlags, setFeatureFlags] = useState<AdminFeatureFlag[]>([]);
  const [resultsQuestionId, setResultsQuestionId] = useState("");
  const [broadcastTitle, setBroadcastTitle] = useState("Today's question is live 🌍");
  const [broadcastBody, setBroadcastBody] = useState("Can you read the world today? Tap to answer and lock your prediction before the reveal.");
  const [broadcastAudience, setBroadcastAudience] = useState<BroadcastAudience>("all");
  const broadcastRoute = "/today";
  const [message, setMessage] = useState("");
  const [busyAction, setBusyAction] = useState("");
  const questionEditorRef = useRef<HTMLElement | null>(null);

  const app = useMemo(() => {
    if (!hasFirebaseConfig()) return null;
    const firebaseApp = getApps()[0] ?? initializeApp(firebaseConfig);
    activateClientAppCheck(firebaseApp);
    return firebaseApp;
  }, []);

  const auth = app ? getAuth(app) : null;
  const firestore = app ? getFirestore(app) : null;
  const functions = app ? getFunctions(app, "us-central1") : null;
  const adminUnlocked = state === "authorized" || devAdminPreview;
  const bankQuestions = useBankQuestions(adminUnlocked ? firestore : null);
  const overviewQuestions = overview?.questions ?? [];
  const liveRows = mergeAdminQuestions(overviewQuestions, questions);
  const rows = liveRows.length > 0 ? liveRows : devAdminPreview ? sampleQuestions : [];
  const worldQuestion = worldDay?.questions.find((question) => !question.pulled) ?? null;
  const worldQuestionAsAdmin = worldQuestion && worldDay
    ? worldDayQuestionToAdminQuestion(worldQuestion, worldDay)
    : null;
  const liveQuestion =
    worldQuestionAsAdmin ??
    rows.find((question) => question.status === "live") ??
    rows[0] ??
    emptyAdminQuestion;
  const nextQuestion =
    nextScheduledQuestion(rows, liveQuestion.dailyKey) ?? (devAdminPreview ? sampleQuestions[1] : emptyAdminQuestion);
  const resultsFocusQuestion = resultsQuestionId
    ? rows.find((question) => question.id === resultsQuestionId) ?? null
    : null;
  const focusedResult = resultsFocusQuestion
    ? resultForQuestion(resultsFocusQuestion.id, overview)
    : overview?.focusResult ?? overview?.results[0] ?? null;
  const resultsQuestion = resultsFocusQuestion ?? (focusedResult ? resultAsQuestion(focusedResult) : liveQuestion);
  const liveDonut = donutForQuestion(liveQuestion, overview);
  const resultDonut = resultsFocusQuestion
    ? donutForQuestion(resultsFocusQuestion, overview)
    : focusedResult ? donutForResult(focusedResult) : liveDonut;
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
    const questionsQuery = query(collection(firestore, "questions"), orderBy("dailyKey", "desc"), limit(120));
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

  useEffect(() => {
    if (!firestore || !adminUnlocked) return undefined;
    return onSnapshot(
      doc(firestore, "rooms", "world"),
      (snapshot) => {
        const data = snapshot.data();
        const nextDailyKey = stringValue(data?.currentDailyKey);
        setWorldCurrentDailyKey(nextDailyKey);
        if (!nextDailyKey) setWorldDay(null);
      },
      (error) => setMessage(error.message),
    );
  }, [adminUnlocked, firestore]);

  useEffect(() => {
    if (!firestore || !adminUnlocked || !worldCurrentDailyKey) return undefined;
    return onSnapshot(
      doc(firestore, "rooms", "world", "days", worldCurrentDailyKey),
      (snapshot) => {
        setWorldDay(snapshot.exists() ? worldDayFromData(snapshot.id, snapshot.data()) : null);
      },
      (error) => setMessage(error.message),
    );
  }, [adminUnlocked, firestore, worldCurrentDailyKey]);

  useEffect(() => {
    if (!firestore || !adminUnlocked) return undefined;
    const daysQuery = query(
      collection(firestore, "rooms", "world", "days"),
      orderBy("dailyKey", "desc"),
      limit(120),
    );
    return onSnapshot(
      daysQuery,
      (snapshot) => {
        setScheduleWorldDays(snapshot.docs
          .map((docSnap) => worldDayFromData(docSnap.id, docSnap.data()))
          .sort((a, b) => a.dailyKey.localeCompare(b.dailyKey)));
      },
      (error) => setMessage(error.message),
    );
  }, [adminUnlocked, firestore]);

  useEffect(() => {
    if (activeView !== "library" || !questionEditorOpen) return;
    questionEditorRef.current?.scrollIntoView({ block: "start", behavior: "smooth" });
  }, [activeQuestionId, activeView, questionEditorOpen]);

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
      if (name === "upsertQuestion" || name === "upsertBankQuestion") {
        const data = objectValue(result.data);
        const savedQuestionId =
          stringValue(data.questionId) ||
          stringValue(data.qid) ||
          stringValue(payload.questionId) ||
          stringValue(payload.qid);
        if (savedQuestionId) {
          setActiveQuestionId(savedQuestionId);
          setQuestionEditorOpen(true);
        }
      }
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
    setLibraryFilter("All");
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
    setPrompt("");
    setCategory(adminCategories[0] ?? "CULTURE");
    setBankTier("normal");
    setBankShape("TASTE");
    setBankActive(true);
    setOptions([
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ]);
  }

  function applyBankQuestion(question: BankQuestion) {
    setQuestionEditorOpen(true);
    setActiveQuestionId(question.id);
    setPrompt(question.prompt);
    setCategory((question.tags[0] ?? adminCategories[0] ?? "CULTURE").toUpperCase());
    setBankTier(question.tier);
    setBankShape(question.shape || "TASTE");
    setBankActive(question.active);
    setOptions([
      { id: "a", label: question.optA || "Yes" },
      { id: "b", label: question.optB || "No" },
    ]);
  }

  function applyQuestion(question: AdminQuestion) {
    setQuestionEditorOpen(true);
    setActiveQuestionId(question.id);
    setPrompt(question.prompt);
    setCategory(question.category);
    setOptions(question.options.length >= 2 ? question.options : [
      { id: "yes", label: "Yes" },
      { id: "no", label: "No" },
    ]);
    if (state === "authorized") {
      void loadOverview(question.id);
    }
  }

  function bankQuestionPayload(activeOverride?: boolean) {
    const normalized = normalizedOptions();
    return {
      qid: activeQuestionId || undefined,
      prompt,
      category,
      tier: bankTier,
      shape: bankShape,
      active: activeOverride ?? bankActive,
      optA: normalized[0]?.label || "Yes",
      optB: normalized[1]?.label || "No",
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
      case "bank":
        return (
          <QuestionBankView
            firestore={firestore}
            functions={functions}
            onMessage={setMessage}
          />
        );
      case "world":
        return (
          <WorldCurationView
            firestore={firestore}
            functions={functions}
            onMessage={setMessage}
          />
        );
      case "rooms":
        return <RoomsOverviewView firestore={firestore} />;
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
    const worldAnswersToday = worldDay?.answerCount;
    const answerCountToday = worldAnswersToday ?? metrics?.answersToday;
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
              <button className="adminBlueButton" onClick={() => {
                if (worldDay) {
                  setActiveView("world");
                } else {
                  setResultsQuestionId(liveQuestion.id);
                  void loadOverview(liveQuestion.id);
                  setActiveView("results");
                }
              }}>
                View live results
              </button>
              <button onClick={() => {
                const bankQuestion = bankQuestions.find((question) => question.id === liveQuestion.id);
                if (bankQuestion) {
                  applyBankQuestion(bankQuestion);
                } else {
                  applyQuestion(liveQuestion);
                }
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
            value={formatCount(answerCountToday, devAdminPreview ? "1,640" : "0")}
            detail={`${formatPercentOf(answerCountToday, metrics?.activeUsers, devAdminPreview ? "87%" : "0%")} of active users`}
          />
          <MetricCard
            label="Predictions locked"
            value={formatCount(answerCountToday ?? metrics?.predictionsLocked, devAdminPreview ? "1,512" : "0")}
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
    const todayKey = defaultWorldScheduleKey();
    const worldDayByKey = new Map(scheduleWorldDays.map((day) => [day.dailyKey, day]));
    const selectedWorldDay = worldDayByKey.get(selectedScheduleDailyKey) ?? null;
    const selectedPicks = scheduleDrafts[selectedScheduleDailyKey] ??
      selectedWorldDay?.questions.map(worldQuestionToSchedulePick) ??
      [];
    const selectedIds = new Set(selectedPicks.map((pick) => pick.qid));
    const activeBankQuestions = bankQuestions.filter((question) => question.active);
    const questionNeedle = scheduleQuestionSearch.trim().toLowerCase();
    const filteredQuestions = activeBankQuestions.filter((question) => {
      if (!questionNeedle) return true;
      return (
        question.prompt.toLowerCase().includes(questionNeedle) ||
        question.optA.toLowerCase().includes(questionNeedle) ||
        question.optB.toLowerCase().includes(questionNeedle) ||
        question.tags.some((tag) => tag.toLowerCase().includes(questionNeedle))
      );
    });
    const questionPageSize = 10;
    const pageCount = Math.max(1, Math.ceil(filteredQuestions.length / questionPageSize));
    const safeQuestionPage = Math.min(scheduleQuestionPage, pageCount - 1);
    const visibleQuestions = filteredQuestions.slice(
      safeQuestionPage * questionPageSize,
      safeQuestionPage * questionPageSize + questionPageSize,
    );
    const calendarCells = monthCalendarCells(scheduleMonthKey);

    function setSelectedDate(dailyKey: string) {
      setSelectedScheduleDailyKey(dailyKey);
      setScheduleMonthKey(dailyKey.slice(0, 7));
      setScheduleQuestionPage(0);
    }

    function setSchedulePicks(nextPicks: WorldSchedulePick[]) {
      setScheduleDrafts((current) => ({
        ...current,
        [selectedScheduleDailyKey]: nextPicks,
      }));
    }

    function addScheduleQuestion(question: BankQuestion) {
      if (selectedIds.has(question.id) || selectedPicks.length >= 3) return;
      setSchedulePicks([
        ...selectedPicks,
        {
          qid: question.id,
          prompt: question.prompt,
          optA: question.optA,
          optB: question.optB,
          tag: question.tags[0] ?? "Everyday",
          tier: question.tier,
          threshold: 1000,
        },
      ]);
    }

    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">World schedule</h1>
            <p>Click a date, then choose the 3 World questions for that day. Gaps are flagged in red.</p>
          </div>
          <div className="adminToolbar">
            <button onClick={() => setScheduleMonthKey(shiftMonthKey(scheduleMonthKey, -1))}>
              ← Previous
            </button>
            <button onClick={() => setScheduleMonthKey(shiftMonthKey(scheduleMonthKey, 1))}>
              Next →
            </button>
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
            <div className="adminViewHead compact">
              <div>
                <div className="adminKicker">The World · {monthLabel(scheduleMonthKey)}</div>
              </div>
            </div>
            <div className="adminWeekdays">
              {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((day) => (
                <span key={day}>{day}</span>
              ))}
            </div>
            <div className="adminCalendar">
              {calendarCells.map((dailyKey, index) => {
                if (!dailyKey) {
                  return <div className="adminCalendarSpacer" key={`blank-${index}`} />;
                }
                const item = worldDayByKey.get(dailyKey) ?? null;
                const savedCount = item?.questions.length ?? 0;
                const draftPicks = scheduleDrafts[dailyKey];
                const draftCount = draftPicks?.length;
                const count = draftCount ?? savedCount;
                const cardPrompts = draftPicks?.map((pick) => pick.prompt) ??
                  item?.questions.map((question) => question.prompt) ??
                  [];
                const needsQuestion = dailyKey >= todayKey && count !== 3;
                const isSelected = dailyKey === selectedScheduleDailyKey;
                const dayLabel = Number(dailyKey.slice(-2));
                return (
                  <button
                    className={[
                      item?.status === "live" ? "live" : "",
                      needsQuestion ? "needsQuestion" : "",
                      isSelected ? "active" : "",
                    ].filter(Boolean).join(" ")}
                    key={dailyKey}
                    onClick={() => setSelectedDate(dailyKey)}
                  >
                    <span>{dayLabel}</span>
                    {count > 0 ? (
                      <strong>
                        {cardPrompts.slice(0, 2).join(" · ") || `${count} selected`}
                      </strong>
                    ) : needsQuestion ? (
                      <em>Needs 3</em>
                    ) : null}
                    {count > 0 ? <em>{count}/3</em> : null}
                  </button>
                );
              })}
            </div>
          </section>
          <aside className="adminDrafts adminWorldScheduler">
            <div className="adminDraftsIntro">
              <span>World room day</span>
              <p>{longDate(selectedScheduleDailyKey) ?? selectedScheduleDailyKey}</p>
            </div>
            <input
              onChange={(event) => setSelectedDate(event.target.value)}
              type="date"
              value={selectedScheduleDailyKey}
            />
            <section className="adminScheduleSelected">
              <PanelHeader label="Selected questions" meta={`${selectedPicks.length}/3`} />
              {selectedPicks.map((pick, index) => (
                <div className="adminSchedulePick" key={pick.qid}>
                  <div>
                    <strong>{index + 1}. {pick.prompt}</strong>
                    <span>{pick.optA} / {pick.optB}</span>
                    <label>
                      Threshold
                      <input
                        min={1}
                        onChange={(event) => {
                          const threshold = Number(event.target.value);
                          setSchedulePicks(selectedPicks.map((entry) =>
                            entry.qid === pick.qid
                              ? { ...entry, threshold: Number.isFinite(threshold) ? Math.round(threshold) : 1000 }
                              : entry));
                        }}
                        type="number"
                        value={pick.threshold}
                      />
                    </label>
                  </div>
                  <button onClick={() => setSchedulePicks(selectedPicks.filter((entry) => entry.qid !== pick.qid))}>
                    Remove
                  </button>
                </div>
              ))}
              {selectedPicks.length === 0 ? <p>No questions selected for this date.</p> : null}
            </section>
            <div className="adminSchedulePickerTop">
              <input
                onChange={(event) => {
                  setScheduleQuestionSearch(event.target.value);
                  setScheduleQuestionPage(0);
                }}
                placeholder="Search all bank questions"
                value={scheduleQuestionSearch}
              />
              <span>{filteredQuestions.length} questions</span>
            </div>
            <section className="adminScheduleQuestionList">
              {visibleQuestions.map((question) => {
                const usage = worldQuestionUsage(question.id, scheduleWorldDays, todayKey);
                return (
                  <div className="adminScheduleQuestionRow" key={question.id}>
                    <div>
                      <strong>{question.prompt}</strong>
                      <span>
                        {question.optA} / {question.optB} · {displayCategory(question.tags[0] ?? "Uncategorized")} · {adminTierLabels[question.tier] ?? question.tier}
                      </span>
                      <em>{worldUsageLabel(usage)}</em>
                    </div>
                    <button
                      disabled={selectedIds.has(question.id) || selectedPicks.length >= 3}
                      onClick={() => addScheduleQuestion(question)}
                    >
                      {selectedIds.has(question.id) ? "Selected" : "Add"}
                    </button>
                  </div>
                );
              })}
            </section>
            <div className="adminSchedulePager">
              <button
                disabled={safeQuestionPage === 0}
                onClick={() => setScheduleQuestionPage((page) => Math.max(0, page - 1))}
              >
                Previous
              </button>
              <span>Page {safeQuestionPage + 1} of {pageCount}</span>
              <button
                disabled={safeQuestionPage >= pageCount - 1}
                onClick={() => setScheduleQuestionPage((page) => Math.min(pageCount - 1, page + 1))}
              >
                Next
              </button>
            </div>
            <button
              className="adminBlueButton"
              disabled={busyAction === "curateWorldDay" || selectedPicks.length !== 3}
              onClick={() => runCallable("curateWorldDay", {
                dailyKey: selectedScheduleDailyKey,
                questions: selectedPicks.map((pick) => ({
                  qid: pick.qid,
                  threshold: pick.threshold,
                })),
              })}
            >
              {busyAction === "curateWorldDay" ? "Saving..." : `Save ${shortDailyKey(selectedScheduleDailyKey)}`}
            </button>
          </aside>
        </div>
      </>
    );
  }

  function renderLibrary() {
    const baseLibraryRows = bankQuestions;
    const libraryRows = baseLibraryRows.filter((question) => {
      if (libraryFilter === "All") return true;
      if (libraryFilter === "Active") return question.active;
      if (libraryFilter === "Retired") return !question.active;
      if (libraryFilter === "Used") return question.timesUsed > 0;
      if (libraryFilter === "Work-safe") return question.tier === "work-safe";
      if (libraryFilter === "Normal") return question.tier === "normal";
      if (libraryFilter === "After Dark") return question.tier === "mature";
      return true;
    });
    return (
      <>
        <div className="adminViewHead">
          <div>
            <h1 className="adminSerif">Question library</h1>
            <p>{baseLibraryRows.length} bank questions · write, edit, and categorize.</p>
          </div>
          <button className="adminBlueButton" onClick={startNewQuestion}>+ New question</button>
        </div>
        {questionEditorOpen ? renderQuestionEditor() : null}
        <div className="adminFilterPills">
          {(["All", "Active", "Retired", "Used", "Work-safe", "Normal", "After Dark"] as LibraryFilter[]).map((label) => (
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
            <span>Used</span>
          </div>
          {libraryRows.map((question) => (
            <button
              className={question.id === activeQuestionId ? "active" : ""}
              key={question.id}
              onClick={() => applyBankQuestion(question)}
            >
              <span>{question.prompt}</span>
              <span><CategoryDot category={question.tags[0] ?? ""} /> {displayCategory(question.tags[0] ?? "Uncategorized")}</span>
              <em data-status={question.active ? "active" : "retired"}>{question.active ? "Active" : "Retired"}</em>
              <span>{question.timesUsed}×</span>
            </button>
          ))}
          {libraryRows.length === 0 ? (
            <div className="adminTableRow">
              <span>No bank questions match this filter.</span>
              <span>--</span>
              <span>--</span>
              <span>--</span>
            </div>
          ) : null}
        </section>
      </>
    );
  }

  function renderAnalytics() {
    const metrics = overview?.metrics;
    const completionRows: AdminDailyCompletionRow[] = overview?.completionRows.length
      ? overview.completionRows
      : devAdminPreview ? previewCompletionRows() : [];
    const latestCompletion = completionRows[completionRows.length - 1] ?? null;
    const bars = normalizedBars(completionRows.map((item) => item.completers));
    const returningRows: Array<[string, number]> = completionRows
      .slice(-7)
      .map((row) => [shortDailyKey(row.label), row.returningPct]);
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
            <span className="active">30D</span>
          </div>
        </div>
        <div className="adminMetricGrid adminAnalyticsMetrics">
          <MetricCard
            label="Completers today"
            value={formatCount(metrics?.dailyCompletersToday ?? latestCompletion?.completers, devAdminPreview ? "1,540" : "0")}
            detail={`${formatCount(metrics?.returningCompletersToday ?? latestCompletion?.returningCompleters, devAdminPreview ? "1,104" : "0")} returning`}
          />
          <MetricCard
            label="Returning today"
            value={formatPercentValue(metrics?.returningCompleterPctToday ?? latestCompletion?.returningPct, devAdminPreview ? "72%" : "0%")}
            detail="Completed on a prior day"
          />
          <MetricCard label="D7 retention" value={formatPercentValue(retentionRows.find(([label]) => label === "D7")?.[1], devAdminPreview ? "38%" : "0%")} detail={devAdminPreview ? "+2.1 pts" : "Streak proxy"} />
          <MetricCard
            label={overview ? "Push tokens" : "Party rounds"}
            value={formatCount(metrics?.notificationTokens, devAdminPreview ? "612" : "0")}
            detail={overview ? `${formatCount(metrics?.waitlistSignups, "0")} waitlist signups` : devAdminPreview ? "+44% MoM" : "0 waitlist signups"}
          />
        </div>
        <section className="adminDesignPanel">
          <PanelHeader
            label="Daily question completers"
            meta={latestCompletion
              ? `${formatCount(latestCompletion.completers)} total · ${formatCount(latestCompletion.returningCompleters)} returning today`
              : "No completions loaded"}
          />
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
            <PanelHeader label="Returning completers" meta="Last 7 days" />
            <ProgressRows rows={returningRows} colorForRow={() => "var(--blue)"} />
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
            <span className="adminStaticPill">00:00 Eastern</span>
          </div>
          <div className="adminSettingRow">
            <div><strong>Results reveal</strong><span>When the world&apos;s answer unlocks</span></div>
            <span className="adminStaticPill">Next day 00:00 Eastern</span>
          </div>
        </section>
        <section className="adminSettingsList adminCategoryPanel">
          <PanelHeader label="Categories" />
          <div className="adminCategoryTags">
            {Object.keys(categoryColors).map((cat) => (
              <span key={cat}><CategoryDot category={cat} /> {displayCategory(cat)}</span>
            ))}
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
    const similarQuestions = similarBankQuestions(prompt, bankQuestions, activeQuestionId);
    return (
      <section className="adminEditor" ref={questionEditorRef}>
        <div className="adminViewHead compact">
          <div>
            <div className="adminKicker">Bank editor</div>
            <h2 className="adminSerif">{activeQuestionId ? "Edit bank question" : "New bank question"}</h2>
          </div>
          <button onClick={() => resetQuestionForm()}>Clear</button>
        </div>
        <div className="adminEditorGrid">
          <label>
            Category
            <select value={category} onChange={(event) => setCategory(event.target.value)}>
              {adminCategories.map((cat) => (
                <option key={cat} value={cat}>{displayCategory(cat)}</option>
              ))}
            </select>
          </label>
          <label>
            Tier
            <select
              value={bankTier}
              onChange={(event) => setBankTier(event.target.value as BankQuestion["tier"])}
            >
              <option value="normal">Normal</option>
              <option value="work-safe">Work-safe</option>
              <option value="mature">After Dark</option>
            </select>
          </label>
          <label>
            Shape
            <select value={bankShape} onChange={(event) => setBankShape(event.target.value)}>
              {bankShapes.map((shape) => (
                <option key={shape} value={shape}>{displayCategory(shape)}</option>
              ))}
            </select>
          </label>
          <label>
            Status
            <select
              value={bankActive ? "active" : "retired"}
              onChange={(event) => {
                const nextActive = event.target.value === "active";
                setBankActive(nextActive);
              }}
            >
              <option value="active">Active</option>
              <option value="retired">Retired</option>
            </select>
          </label>
          <label className="wide">
            Prompt
            <textarea value={prompt} onChange={(event) => setPrompt(event.target.value)} />
          </label>
          <div className="wide optionEditor">
            <div className="optionEditorTop">
              <span>Options</span>
            </div>
            {options.slice(0, 2).map((option, index) => (
              <div className="optionRow" key={index}>
                <span>{index === 0 ? "A" : "B"}</span>
                <input
                  aria-label={`Option ${index + 1} label`}
                  value={option.label}
                  onChange={(event) => updateOption(index, "label", event.target.value)}
                />
              </div>
            ))}
          </div>
        </div>
        <section className="adminSimilarityPanel">
          <PanelHeader
            label="Similar questions"
            meta={prompt.trim() ? `${similarQuestions.length} possible matches` : "Start typing to check duplicates"}
          />
          {similarQuestions.map((question) => (
            <button key={question.id} type="button" onClick={() => applyBankQuestion(question)}>
              <span>{question.prompt}</span>
              <em>{question.score}% similar</em>
            </button>
          ))}
          {prompt.trim().length >= 8 && similarQuestions.length === 0 ? (
            <p>No close matches found.</p>
          ) : null}
        </section>
        <div className="adminActions">
          <button
            className="adminBlueButton"
            disabled={Boolean(busyAction)}
            onClick={() => runCallable("upsertBankQuestion", bankQuestionPayload(true))}
          >
            <Save size={17} /> {busyAction === "upsertBankQuestion" ? "Saving..." : "Save active"}
          </button>
          <button disabled={Boolean(busyAction)} onClick={() => runCallable("upsertBankQuestion", bankQuestionPayload(false))}>
            Retire
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

function defaultWorldScheduleKey() {
  return new Date().toLocaleDateString("en-CA", { timeZone: "America/Toronto" });
}

function monthCalendarCells(monthKey: string): Array<string | null> {
  const match = /^(\d{4})-(\d{2})$/.exec(monthKey);
  if (!match) return [];
  const year = Number(match[1]);
  const monthIndex = Number(match[2]) - 1;
  const firstDay = new Date(Date.UTC(year, monthIndex, 1));
  const daysInMonth = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
  const cells: Array<string | null> = Array.from({ length: firstDay.getUTCDay() }, () => null);
  for (let day = 1; day <= daysInMonth; day += 1) {
    cells.push(`${monthKey}-${String(day).padStart(2, "0")}`);
  }
  while (cells.length % 7 !== 0) cells.push(null);
  return cells;
}

function shiftMonthKey(monthKey: string, delta: number) {
  const match = /^(\d{4})-(\d{2})$/.exec(monthKey);
  if (!match) return defaultWorldScheduleKey().slice(0, 7);
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1 + delta, 1));
  return date.toISOString().slice(0, 7);
}

function monthLabel(monthKey: string) {
  const date = parseDailyKey(`${monthKey}-01`);
  if (!date) return monthKey;
  return new Intl.DateTimeFormat("en", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

function worldQuestionToSchedulePick(question: AdminWorldDayQuestion): WorldSchedulePick {
  return {
    qid: question.qid,
    prompt: question.prompt,
    optA: question.optA,
    optB: question.optB,
    tag: question.tag,
    tier: question.tier,
    threshold: question.threshold ?? 1000,
  };
}

function worldQuestionUsage(
  qid: string,
  days: AdminWorldDay[],
  todayKey: string,
): { usedKeys: string[]; scheduledKeys: string[] } {
  const usedKeys: string[] = [];
  const scheduledKeys: string[] = [];
  for (const day of days) {
    if (!day.questions.some((question) => question.qid === qid)) continue;
    if (day.dailyKey <= todayKey && day.status !== "scheduled") {
      usedKeys.push(day.dailyKey);
    } else {
      scheduledKeys.push(day.dailyKey);
    }
  }
  return { usedKeys, scheduledKeys };
}

function worldUsageLabel(usage: { usedKeys: string[]; scheduledKeys: string[] }) {
  const latestUsed = usage.usedKeys[usage.usedKeys.length - 1];
  if (latestUsed) {
    return `Used in World ${usage.usedKeys.length}× · latest ${shortDailyKey(latestUsed)}`;
  }
  const nextScheduled = usage.scheduledKeys[0];
  if (nextScheduled) return `Scheduled for World · ${shortDailyKey(nextScheduled)}`;
  return "Never used in World";
}

function mergeAdminQuestions(...groups: AdminQuestion[][]) {
  const byId = new Map<string, AdminQuestion>();
  for (const group of groups) {
    for (const question of group) {
      if (!question.id) continue;
      byId.set(question.id, {
        ...(byId.get(question.id) ?? {}),
        ...question,
      });
    }
  }
  return [...byId.values()].sort((a, b) => compareDailyKeysDesc(a.dailyKey, b.dailyKey));
}

function nextScheduledQuestion(rows: AdminQuestion[], currentDailyKey: string) {
  return rows
    .filter((question) => question.status === "scheduled")
    .sort((a, b) => compareDailyKeysAsc(a.dailyKey, b.dailyKey))
    .find((question) => !currentDailyKey || question.dailyKey > currentDailyKey) ?? null;
}

function compareDailyKeysDesc(a: string, b: string) {
  return compareDailyKeysAsc(b, a);
}

function compareDailyKeysAsc(a: string, b: string) {
  return (a || "9999-99-99").localeCompare(b || "9999-99-99");
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

function worldDayFromData(id: string, data: DocumentData | undefined): AdminWorldDay {
  const record = objectValue(data);
  return {
    dailyKey: stringValue(record.dailyKey) || id,
    status: stringValue(record.status) || "live",
    answerCount: numberValue(record.answerCount),
    answerCounts: numberRecord(record.answerCounts),
    questions: arrayValue(record.questions).map(worldDayQuestionFromData),
  };
}

function worldDayQuestionFromData(value: unknown): AdminWorldDayQuestion {
  const record = objectValue(value);
  return {
    qid: stringValue(record.qid),
    prompt: stringValue(record.prompt),
    optA: stringValue(record.optA) || "Yes",
    optB: stringValue(record.optB) || "No",
    tag: stringValue(record.tag) || "Daily read",
    tier: stringValue(record.tier) || "normal",
    threshold: nullableNumber(record.threshold),
    pulled: record.pulled === true,
  };
}

function worldDayQuestionToAdminQuestion(
  question: AdminWorldDayQuestion,
  day: AdminWorldDay,
): AdminQuestion {
  return {
    id: question.qid,
    prompt: question.prompt,
    category: question.tag,
    status: day.status || "live",
    dailyKey: day.dailyKey,
    publishAt: "",
    closeAt: revealAtForDailyKey(day.dailyKey) ?? "",
    options: [
      { id: "a", label: question.optA },
      { id: "b", label: question.optB },
    ],
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
    completionRows: arrayValue(record.completionRows).map(completionRowFromData),
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
    dailyCompletersToday: numberValue(record.dailyCompletersToday),
    returningCompletersToday: numberValue(record.returningCompletersToday),
    returningCompleterPctToday: numberValue(record.returningCompleterPctToday),
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

function completionRowFromData(value: unknown): AdminDailyCompletionRow {
  const record = objectValue(value);
  return {
    label: stringValue(record.label),
    completers: numberValue(record.completers),
    returningCompleters: numberValue(record.returningCompleters),
    newCompleters: numberValue(record.newCompleters),
    returningPct: numberValue(record.returningPct),
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

function previewCompletionRows(): AdminDailyCompletionRow[] {
  const start = new Date(Date.UTC(2026, 5, 6));
  return Array.from({ length: 30 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    const completers = 820 + Math.round(index * 23 + Math.sin(index / 3) * 80);
    const returningPct = clampPercent(54 + Math.round(index * 0.6 + Math.sin(index / 4) * 6));
    const returningCompleters = Math.round((completers * returningPct) / 100);
    return {
      label: date.toISOString().slice(0, 10),
      completers,
      returningCompleters,
      newCompleters: Math.max(0, completers - returningCompleters),
      returningPct,
    };
  });
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

function shortDailyKey(value: string) {
  const dailyKey = parseDailyKey(value);
  if (!dailyKey) return value || "--";
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(dailyKey);
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

function revealAtForDailyKey(dailyKey: string) {
  const date = parseDailyKey(dailyKey);
  if (!date) return null;
  const nextDay = new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate() + 1,
  ));
  const offsetMinutes = easternOffsetMinutesForDate(nextDay);
  const revealUtc = Date.UTC(
    nextDay.getUTCFullYear(),
    nextDay.getUTCMonth(),
    nextDay.getUTCDate(),
  ) - offsetMinutes * 60 * 1000;
  return new Date(revealUtc).toISOString();
}

function easternOffsetMinutesForDate(date: Date) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Toronto",
    timeZoneName: "shortOffset",
    hour: "2-digit",
  }).formatToParts(date);
  const offset = parts.find((part) => part.type === "timeZoneName")?.value ?? "GMT";
  const match = /^GMT([+-])(\d{1,2})(?::(\d{2}))?$/.exec(offset);
  if (!match) return 0;
  const sign = match[1] === "-" ? -1 : 1;
  return sign * (Number(match[2]) * 60 + Number(match[3] ?? 0));
}

function validatePayload(name: string, payload: Record<string, unknown>) {
  if (name === "upsertBankQuestion") {
    if (!stringValue(payload.prompt)) return "Prompt is required.";
    if (!stringValue(payload.category)) return "Category is required.";
    if (!stringValue(payload.optA) || !stringValue(payload.optB)) {
      return "Both response labels are required.";
    }
    return "";
  }
  if (name !== "upsertQuestion") {
    if ((name === "closeQuestionNow" || name === "recomputeQuestion") && !stringValue(payload.questionId)) {
      return "Choose a question before running this action.";
    }
    return "";
  }
  if (!stringValue(payload.questionId)) return "Question ID is required.";
  if (!stringValue(payload.prompt)) return "Prompt is required.";
  if (!stringValue(payload.category)) return "Category is required.";
  const status = stringValue(payload.status) || "draft";
  if (status !== "draft" && !stringValue(payload.dailyKey)) {
    return "Daily key is required before a question is scheduled.";
  }
  if (status !== "draft" && (!stringValue(payload.publishAt) || !stringValue(payload.closeAt))) {
    return "Publish and close dates are required before scheduling.";
  }
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

function normalizedPromptWords(value: string): string[] {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((word) => word.length >= 3);
}

function normalizedPromptKey(value: string): string {
  return normalizedPromptWords(value).join(" ");
}

function similarBankQuestions(
  prompt: string,
  questions: BankQuestion[],
  activeQuestionId: string,
): Array<BankQuestion & { score: number }> {
  const key = normalizedPromptKey(prompt);
  if (key.length < 8) return [];
  const words = new Set(normalizedPromptWords(prompt));
  if (words.size === 0) return [];
  return questions
    .filter((question) => question.id !== activeQuestionId)
    .map((question) => {
      const questionKey = normalizedPromptKey(question.prompt);
      if (questionKey === key) return { ...question, score: 100 };
      const questionWords = new Set(normalizedPromptWords(question.prompt));
      const overlap = [...words].filter((word) => questionWords.has(word)).length;
      const denominator = Math.max(words.size, questionWords.size, 1);
      const score = Math.round((overlap / denominator) * 100);
      return { ...question, score };
    })
    .filter((question) => question.score >= 35)
    .sort((a, b) => b.score - a.score || a.prompt.localeCompare(b.prompt))
    .slice(0, 6);
}
