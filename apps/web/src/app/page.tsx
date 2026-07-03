"use client";

import { FirebaseError, getApps, initializeApp, type FirebaseApp } from "firebase/app";
import Image from "next/image";
import {
  collection,
  doc,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
  where,
} from "firebase/firestore";
import {
  createUserWithEmailAndPassword,
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  type User,
} from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { useEffect, useMemo, useState } from "react";
import { activateClientAppCheck } from "@/lib/appCheck";

const faqs = [
  [
    "Is it the same questions for everyone?",
    "Yes. Every player worldwide gets the same three questions each day, so you are always reading the same global crowd.",
  ],
  [
    "Why don't results show right away?",
    "Results arrive the next day, when the new questions drop. You commit your read before you see how it landed.",
  ],
  [
    "How is my score calculated?",
    "Your Read Score rewards how close your prediction was to the actual global result, not whether you agreed with the majority.",
  ],
  [
    "Is it free?",
    "Yes. Three questions a day, free. Create an account to save your streak, track your score, and compare with friends.",
  ],
];

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const appBaseUrl = "https://app.readtheworld.today";

/** One of today's three World questions (rooms/world/days/{key}). */
type WorldQuestion = {
  qid: string;
  tag: string;
  prompt: string;
  optA: string;
  optB: string;
};

type PublicQuestion = { id: string; category: string; prompt: string };

const sampleQuestions: PublicQuestion[] = [
  { id: "s1", category: "Food", prompt: "Is a hot dog a sandwich?" },
  { id: "s2", category: "Ethics", prompt: "Would you keep quiet if you saw a friend shoplift a small item?" },
  { id: "s3", category: "Lifestyle", prompt: "Would you rather always be 10 minutes early or never rushed?" },
];

function hasFirebaseConfig() {
  return Object.values(firebaseConfig).every(Boolean);
}

export default function Home() {
  const [step, setStep] = useState<"answer" | "gate">("answer");
  const [qIndex, setQIndex] = useState(0);
  const [sides, setSides] = useState<Record<string, "a" | "b">>({});
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [footerEmail, setFooterEmail] = useState("");
  const [submitError, setSubmitError] = useState("");
  const [submitting, setSubmitting] = useState<"" | "gate">("");
  const [openFaq, setOpenFaq] = useState(0);
  const [worldQuestions, setWorldQuestions] = useState<WorldQuestion[]>([]);
  const [worldDailyKey, setWorldDailyKey] = useState("");
  const [recentQuestions, setRecentQuestions] = useState<PublicQuestion[]>([]);
  const [liveCount, setLiveCount] = useState(0);
  const [user, setUser] = useState<User | null>(null);
  const app = useMemo<FirebaseApp | null>(() => {
    if (!hasFirebaseConfig()) return null;
    const firebaseApp = getApps()[0] ?? initializeApp(firebaseConfig);
    activateClientAppCheck(firebaseApp);
    return firebaseApp;
  }, []);
  const firestore = useMemo(() => (app ? getFirestore(app) : null), [app]);
  const auth = useMemo(() => (app ? getAuth(app) : null), [app]);
  const functions = useMemo(() => (app ? getFunctions(app, "us-central1") : null), [app]);

  // The World's current daily key, then today's three questions.
  useEffect(() => {
    if (!firestore) return undefined;
    return onSnapshot(doc(firestore, "rooms", "world"), (snapshot) => {
      setWorldDailyKey(String(snapshot.data()?.currentDailyKey ?? ""));
    });
  }, [firestore]);

  useEffect(() => {
    if (!firestore || !worldDailyKey) return undefined;
    return onSnapshot(doc(firestore, "rooms", "world", "days", worldDailyKey), (snapshot) => {
      const data = snapshot.data();
      const questions = Array.isArray(data?.questions) ? data.questions : [];
      setWorldQuestions(
        questions
          .filter((question) => question?.pulled !== true)
          .map((question) => ({
            qid: String(question?.qid ?? ""),
            tag: String(question?.tag ?? "Today"),
            prompt: String(question?.prompt ?? ""),
            optA: String(question?.optA ?? "Yes"),
            optB: String(question?.optB ?? "No"),
          }))
          .filter((question) => question.qid && question.prompt),
      );
      const total = Number(data?.answerCount ?? 0);
      setLiveCount(Number.isFinite(total) ? total : 0);
    });
  }, [firestore, worldDailyKey]);

  // Recent world reveals fill the archive strip once days start closing.
  useEffect(() => {
    if (!firestore) return undefined;
    const recentQuery = query(
      collection(firestore, "rooms", "world", "days"),
      where("status", "==", "closed"),
      orderBy("dailyKey", "desc"),
      limit(2),
    );
    return onSnapshot(recentQuery, (snapshot) => {
      const closed: PublicQuestion[] = [];
      snapshot.docs.forEach((docSnap) => {
        const questions = Array.isArray(docSnap.data().questions) ? docSnap.data().questions : [];
        questions.forEach((question: Record<string, unknown>, index: number) => {
          const prompt = String(question?.prompt ?? "");
          if (prompt) {
            closed.push({
              id: `${docSnap.id}-${index}`,
              category: String(question?.tag ?? "Daily read"),
              prompt,
            });
          }
        });
      });
      setRecentQuestions(closed.slice(0, 6));
    }, () => setRecentQuestions([]));
  }, [firestore]);

  useEffect(() => {
    if (!auth) return undefined;
    return onAuthStateChanged(auth, (nextUser) => {
      setUser(nextUser);
      if (nextUser?.email) setEmail((current) => current || nextUser.email || "");
    });
  }, [auth]);

  const currentQuestion = worldQuestions[qIndex] ?? null;
  const navCtaLabel = !user ? "Log in" : "Enter app";

  function pick(side: "a" | "b") {
    if (!currentQuestion) return;
    setSides((current) => ({ ...current, [currentQuestion.qid]: side }));
    setSubmitError("");
    if (qIndex + 1 < worldQuestions.length) {
      setQIndex(qIndex + 1);
    } else {
      setStep("gate");
    }
  }

  async function signInOrCreateLandingUser(normalizedEmail: string, nextPassword: string) {
    if (!auth) throw new Error("Live authentication is unavailable.");
    try {
      return await signInWithEmailAndPassword(auth, normalizedEmail, nextPassword);
    } catch (signInError) {
      if (!(signInError instanceof FirebaseError)) throw signInError;
      if (!["auth/invalid-credential", "auth/user-not-found", "auth/wrong-password"].includes(signInError.code)) {
        throw signInError;
      }
      try {
        return await createUserWithEmailAndPassword(auth, normalizedEmail, nextPassword);
      } catch (createError) {
        if (createError instanceof FirebaseError && createError.code === "auth/email-already-in-use") {
          throw new Error("Email or password was not recognized.");
        }
        throw createError;
      }
    }
  }

  async function createAppHandoff(targetRoute: string) {
    if (!functions) return `${appBaseUrl}${targetRoute}`;
    const callable = httpsCallable(functions, "createAuthHandoff");
    const result = await callable({ targetRoute });
    const data = result.data as { code?: unknown };
    const code = typeof data.code === "string" ? data.code : "";
    if (!code) throw new Error("Could not create app handoff.");
    const params = new URLSearchParams({ handoff: code, next: targetRoute });
    return `${appBaseUrl}/auth?${params.toString()}`;
  }

  async function enterApp(targetRoute: string) {
    if (!user) {
      window.location.href = `${appBaseUrl}/auth`;
      return;
    }
    setSubmitting("gate");
    setSubmitError("");
    try {
      window.location.href = await createAppHandoff(targetRoute);
    } catch (error) {
      setSubmitError(error instanceof FirebaseError ? error.message : String(error));
      setSubmitting("");
    }
  }

  async function completeLandingPlay() {
    const picks = worldQuestions
      .filter((question) => sides[question.qid])
      .map((question) => ({ qid: question.qid, side: sides[question.qid] }));
    if (picks.length !== worldQuestions.length || picks.length === 0) {
      setSubmitError("Answer all three questions first.");
      return;
    }

    setSubmitError("");
    setSubmitting("gate");
    try {
      if (!user) {
        const normalizedEmail = email.trim().toLowerCase();
        const normalizedPassword = password;
        if (!normalizedEmail.includes("@")) {
          setSubmitError("Enter a valid email address.");
          setSubmitting("");
          return;
        }
        if (normalizedPassword.length < 6) {
          setSubmitError("Enter your password.");
          setSubmitting("");
          return;
        }
        await signInOrCreateLandingUser(normalizedEmail, normalizedPassword);
      }
      // Record the three world answers (The World auto-enrolls on first
      // answer). If they already answered today the lock is a no-op.
      if (functions) {
        try {
          await httpsCallable(functions, "lockRoomAnswers")({ roomId: "world", picks });
        } catch (lockError) {
          const code = lockError instanceof FirebaseError ? lockError.code : "";
          if (!code.includes("already-exists")) console.warn("World lock failed", lockError);
        }
      }
      window.location.href = await createAppHandoff("/today");
    } catch (error) {
      const message = error instanceof FirebaseError ? authErrorMessage(error) : String(error);
      setSubmitError(message);
      setSubmitting("");
    }
  }

  function startCreateAccount(nextEmail: string) {
    const normalizedEmail = nextEmail.trim();
    if (!normalizedEmail.includes("@")) {
      setSubmitError("Enter a valid email address.");
      return;
    }

    const params = new URLSearchParams({
      mode: "create",
      email: normalizedEmail,
    });
    window.location.href = `${appBaseUrl}/auth?${params.toString()}`;
  }

  return (
    <main className="landing">
      <header className="lpNav">
        <div className="lpWrap lpNavInner">
          <a className="wordmark" href="#play" aria-label="Read the World home">
            read the world<span>.</span>
          </a>
          <nav aria-label="Primary">
            <a href="#how">How it works</a>
            <a href="#score">Read Score</a>
            <a href="#party">Party mode</a>
            <a href="#faq">FAQ</a>
          </nav>
          <div className="lpNavActions">
            {user ? (
              <button
                className="textNavButton lpHideMobile"
                type="button"
                onClick={() => enterApp("/account")}
                disabled={submitting === "gate"}
              >
                Account
              </button>
            ) : null}
            <button
              className="darkButton"
              type="button"
              onClick={() => enterApp(!user ? "/auth" : "/today")}
              disabled={submitting === "gate"}
            >
              {navCtaLabel} {"\u2192"}
            </button>
          </div>
        </div>
      </header>

      <section className="lpWrap lpHero" id="play">
        <div className="lpPitch">
          <div className="eyebrow clay">A daily game of public opinion</div>
          <h1 className="serif">
            You know what you think.
            <br />
            But can you read
            <br />
            the world?
          </h1>
          <p>
            Three shared questions a day. Answer for yourself, then see how the
            world answers. The closer your read, the higher your score.
          </p>
        </div>

        <div className="liveCardColumn">
          <section className="liveCard" aria-label="Live question">
            <div className="questionTop">
              <span>
                Today{currentQuestion ? ` · ${currentQuestion.tag}` : ""}
                {step === "answer" && worldQuestions.length > 0
                  ? ` · ${Math.min(qIndex + 1, worldQuestions.length)} of ${worldQuestions.length}`
                  : ""}
              </span>
              <span className="liveDot"><i />Live</span>
            </div>
            {step === "answer" ? (
              <h2 className="serif">{currentQuestion?.prompt ?? "Loading today's questions..."}</h2>
            ) : (
              <h2 className="serif">That&apos;s your three in.</h2>
            )}

            {step === "answer" ? (
              <div className="answerStep">
                <p>{qIndex === 0 ? "First, where do you stand?" : "Where do you stand?"}</p>
                {currentQuestion ? (
                  <>
                    <button
                      className={sides[currentQuestion.qid] === "a" ? "selected" : ""}
                      onClick={() => pick("a")}
                    >
                      {currentQuestion.optA}
                    </button>
                    <button
                      className={sides[currentQuestion.qid] === "b" ? "selected" : ""}
                      onClick={() => pick("b")}
                    >
                      {currentQuestion.optB}
                    </button>
                  </>
                ) : null}
              </div>
            ) : null}

            {step === "gate" ? (
              <div className="gateStep">
                <div className="gateBox">
                  <div>
                    {worldQuestions.map((question) => (
                      <span key={question.qid}>
                        {question.tag} &middot;{" "}
                        {sides[question.qid] === "a" ? question.optA : question.optB}
                      </span>
                    ))}
                  </div>
                  <p>
                    Sign in or create a free account to save your reads, keep your
                    streak going, and be first in when the world&apos;s answers unlock.
                  </p>
                </div>
                {user ? (
                  <div className="gateForm accountGate">
                    <button
                      disabled={submitting === "gate"}
                      onClick={completeLandingPlay}
                    >
                      {submitting === "gate" ? "Opening app..." : `Continue as ${user.email ?? "this account"}`}
                    </button>
                  </div>
                ) : (
                  <div className="gateForm stacked">
                    <input
                      value={email}
                      onChange={(event) => setEmail(event.target.value)}
                      placeholder="you@email.com"
                      type="email"
                      autoComplete="email"
                    />
                    <input
                      value={password}
                      onChange={(event) => setPassword(event.target.value)}
                      placeholder="Password"
                      type="password"
                      autoComplete="current-password"
                    />
                    <button
                      disabled={submitting === "gate"}
                      onClick={completeLandingPlay}
                    >
                      {submitting === "gate" ? "Opening app..." : "Continue"}
                    </button>
                  </div>
                )}
                {submitError ? <p className="formError">{submitError}</p> : null}
                <button
                  className="ghostButton left"
                  onClick={() => {
                    setQIndex(0);
                    setStep("answer");
                  }}
                >
                  {"\u2190"} Change my answers
                </button>
              </div>
            ) : null}
          </section>
          {worldQuestions.length > 0 && liveCount > 0 ? (
            <div className="liveCount">{liveCount.toLocaleString()} people have answered today</div>
          ) : null}
        </div>
      </section>

      <section className="lpBand" id="how">
        <div className="lpWrap lpSection">
          <div className="sectionHead">
            <div className="eyebrow">The daily ritual</div>
            <h2 className="serif">
              Two taps a day.
              <br />
              One shared moment.
            </h2>
          </div>
          <div className="ritualGrid">
            <article>
              <b className="serif">01</b>
              <h3 className="serif">Answer</h3>
              <p>Take your own side on today&apos;s question. It stays private and starts your read.</p>
            </article>
            <article>
              <b className="serif">02</b>
              <h3 className="serif">Predict</h3>
              <p>Guess what share of the world answered the same way. That prediction is the game.</p>
            </article>
            <article>
              <b className="serif">03</b>
              <h3 className="serif">Reveal</h3>
              <p>Tomorrow, see how the world answered and how close your read was.</p>
            </article>
          </div>
        </div>
      </section>

      <section className="lpWrap lpSection lpCols" id="score">
        <div>
          <div className="eyebrow clay">Your Read Score</div>
          <h2 className="serif">It&apos;s not about being right. It&apos;s about reading the room.</h2>
          <p>
            Points reward how accurately you predict public opinion, not whether
            you sided with the majority. Climb the global and friends
            leaderboards as you learn to read society.
          </p>
        </div>
        <div className="leaderboard">
          <div className="leaderHead">Friends leaderboard</div>
          <div className="me">
            <span>1</span>
            <strong>You</strong>
            <b className="serif">1,840</b>
          </div>
          <div>
            <span>2</span>
            <strong>Dana K.</strong>
            <b className="serif">1,792</b>
          </div>
          <div>
            <span>3</span>
            <strong>Marcus R.</strong>
            <b className="serif">1,710</b>
          </div>
          <div>
            <span>4</span>
            <strong>Priya S.</strong>
            <b className="serif">1,655</b>
          </div>
        </div>
      </section>

      <section className="partyBand" id="party">
        <div className="lpWrap lpSection lpCols">
          <div>
            <div className="eyebrow onDark">Party mode</div>
            <h2 className="serif">Read the room, together.</h2>
            <p>
              Throw it on a screen and run through past questions, solo or with
              a room. Reveal how the world really answered, one card at a time.
              No scores, just the read.
            </p>
          </div>
          <div className="partyDeck" aria-label="Sample party mode question deck">
            <div className="partyCard partyCardBack partyCardBackLeft">
              <div className="eyebrow onDark">Philosophy</div>
              <h3 className="serif">Do you believe in free will?</h3>
              <div className="partyResult partyResultGhost" />
            </div>
            <div className="partyCard partyCardBack partyCardBackRight">
              <div className="eyebrow onDark">Society</div>
              <h3 className="serif">Should billionaires exist?</h3>
              <div className="partyResult partyResultGhost" />
            </div>
            <div className="partyCard partyCardFront">
              <div className="partyCardTop">
                <div className="eyebrow onDark">Culture</div>
                <span>3 / 56</span>
              </div>
              <h3 className="serif">Is it rude to keep your phone on the table at dinner?</h3>
              <div className="partyResult">
                <div className="yesFill" />
                <b>YES 62%</b>
                <em>NO</em>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="downloadBand" id="downloads">
        <div className="lpWrap lpSection lpCols downloadSection">
          <div>
            <div className="eyebrow clay">Take it with you</div>
            <h2 className="serif">The daily read, in your pocket.</h2>
            <p>
              Native apps are on the way. Until then, the full daily challenge
              runs right in your browser. No download needed.
            </p>
            <a className="darkButton downloadWebButton" href="#play">
              Play today&apos;s questions <span aria-hidden="true">→</span>
            </a>
          </div>
          <div className="downloadCards" aria-label="Upcoming app downloads">
            <article className="storeCard">
              <Image className="storeMark appleMark" src="/apple-mark.svg" width={32} height={32} alt="" aria-hidden="true" />
              <div>
                <div className="eyebrow">App Store</div>
                <h3 className="serif">iPhone &amp; iPad</h3>
              </div>
              <b>Soon</b>
            </article>
            <article className="storeCard">
              <Image className="storeMark" src="/google-play-mark.svg" width={30} height={30} alt="" aria-hidden="true" />
              <div>
                <div className="eyebrow">Google Play</div>
                <h3 className="serif">Android</h3>
              </div>
              <b>Soon</b>
            </article>
            <p>Create an account and we&apos;ll let you know the moment the apps go live.</p>
          </div>
        </div>
      </section>

      <section className="lpWrap lpSection">
        <div className="sectionHead">
          <div className="eyebrow">Every topic, every day</div>
          <h2 className="serif">Questions worth arguing about.</h2>
        </div>
        <div className="sampleGrid">
          {(recentQuestions.length > 0 ? recentQuestions : sampleQuestions).map((question) => (
            <article key={question.id}>
              <div className="eyebrow clay">{question.category}</div>
              <h3 className="serif">{question.prompt}</h3>
            </article>
          ))}
        </div>
      </section>

      <section className="lpBand" id="faq">
        <div className="lpWrap lpSection faqSection">
          <h2 className="serif">Questions about the questions</h2>
          <div className="faqList">
            {faqs.map(([question, answerText], index) => (
              <div className="faqItem" key={question}>
                <button onClick={() => setOpenFaq(openFaq === index ? -1 : index)}>
                  <span>{question}</span>
                  <b className={openFaq === index ? "open" : ""}>+</b>
                </button>
                {openFaq === index ? <p>{answerText}</p> : null}
              </div>
            ))}
          </div>
        </div>
      </section>

      <footer className="lpWrap lpSection footerCta">
        <h2 className="serif">Today&apos;s questions are waiting.</h2>
        <p>Join the daily read. Free, three questions a day.</p>
        <form
          onSubmit={async (event) => {
            event.preventDefault();
            startCreateAccount(footerEmail);
          }}
        >
          <input
            value={footerEmail}
            onChange={(event) => setFooterEmail(event.target.value)}
            placeholder="you@email.com"
            type="email"
          />
          <button type="submit">
            Get started
          </button>
        </form>
        {submitError ? (
          <div className="footerSuccess error">{submitError}</div>
        ) : null}
        <div className="footerBottom">
          <a className="wordmark" href="#play">
            read the world<span>.</span>
          </a>
          <span>&copy; 2026 &middot; A daily game of public opinion</span>
        </div>
      </footer>
    </main>
  );
}

function authErrorMessage(error: FirebaseError) {
  switch (error.code) {
    case "auth/invalid-email":
      return "Enter a valid email address.";
    case "auth/weak-password":
      return "Use a stronger password.";
    case "auth/email-already-in-use":
    case "auth/invalid-credential":
    case "auth/user-not-found":
    case "auth/wrong-password":
      return "Email or password was not recognized.";
    case "auth/network-request-failed":
      return "Network error. Try again.";
    default:
      return error.message;
  }
}
