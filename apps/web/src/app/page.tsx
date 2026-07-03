"use client";

import { FirebaseError, getApps, initializeApp, type FirebaseApp } from "firebase/app";
import Image from "next/image";
import { doc, getFirestore, onSnapshot } from "firebase/firestore";
import {
  createUserWithEmailAndPassword,
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  type User,
} from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { useEffect, useMemo, useRef, useState } from "react";
import { activateClientAppCheck } from "@/lib/appCheck";

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

const argueQuestions: PublicQuestion[] = [
  { id: "s1", category: "Food & Drink", prompt: "Is a hot dog a sandwich?" },
  { id: "s2", category: "Ethics", prompt: "Would you tell a friend if their partner was cheating?" },
  { id: "s3", category: "Psychology", prompt: "Do you think you're an above-average driver?" },
  { id: "s4", category: "Travel", prompt: "Is it okay to recline your seat on a short flight?" },
  { id: "s5", category: "Money", prompt: "Would you take $1M to never use the internet again?" },
  { id: "s6", category: "Values", prompt: "Would you rather your kids be happy or successful?" },
];

const faqs: Array<[string, string]> = [
  [
    "What exactly is a room?",
    "Your crew: friends, family, coworkers, teammates. Everyone gets the same three questions, answers for themselves, and predicts the split. Reveal the next morning.",
  ],
  [
    "Does everyone get the same questions?",
    "Everyone in a room plays the same three. Each room's set is its own, tuned to its spice level and topics. The World gets one shared set for everyone on Earth.",
  ],
  [
    "Why don't results show right away?",
    "You commit your read first. Reveals land 24 hours later, with the next day's questions. No peeking, no herding.",
  ],
  [
    "Can I keep it work-safe?",
    "Yes. Every room sets its own spice level: Work-safe, Everyday, or After Dark, plus topic filters. The office room stays HR-approved; the group chat can do whatever it wants.",
  ],
  [
    "What's the World Room?",
    "One room with everyone in it. Answering is open now. Predicting unlocks the moment 5,000 players are in.",
  ],
  [
    "How is my Read Score calculated?",
    "The closer your prediction lands to the real split, the more points you take from the reveal. Wins move you up the room's leaderboard.",
  ],
  [
    "Is it free?",
    "Yes. Three questions a day, free. Create an account to save your streak, track your score, and play with your crew.",
  ],
];

function hasFirebaseConfig() {
  return Object.values(firebaseConfig).every(Boolean);
}

/** Animates a number from 0 the first time it scrolls into view. */
function CountUp({ value, duration = 1100 }: { value: number; duration?: number }) {
  const ref = useRef<HTMLSpanElement | null>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const node = ref.current;
    if (!node) return undefined;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setProgress(1);
      return undefined;
    }
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      const startedAt = performance.now();
      const tick = (now: number) => {
        const raw = Math.min(1, (now - startedAt) / duration);
        setProgress(1 - Math.pow(1 - raw, 3));
        if (raw < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }, { threshold: 0.4 });
    observer.observe(node);
    return () => observer.disconnect();
  }, [duration]);

  return <span ref={ref}>{Math.round(value * progress).toLocaleString()}</span>;
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
  const [liveCount, setLiveCount] = useState(0);
  const [worldMembers, setWorldMembers] = useState(0);
  const [worldGoal, setWorldGoal] = useState(5000);
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

  // The World's current daily key, member counter, then today's questions.
  useEffect(() => {
    if (!firestore) return undefined;
    return onSnapshot(doc(firestore, "rooms", "world"), (snapshot) => {
      const data = snapshot.data();
      setWorldDailyKey(String(data?.currentDailyKey ?? ""));
      const members = Number(data?.memberCount ?? 0);
      const goal = Number(data?.worldGoal ?? 5000);
      setWorldMembers(Number.isFinite(members) ? members : 0);
      setWorldGoal(Number.isFinite(goal) && goal > 0 ? goal : 5000);
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

  useEffect(() => {
    if (!auth) return undefined;
    return onAuthStateChanged(auth, (nextUser) => {
      setUser(nextUser);
      if (nextUser?.email) setEmail((current) => current || nextUser.email || "");
    });
  }, [auth]);

  const [navScrolled, setNavScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setNavScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  // Scroll-reveal: sections rise in the first time they enter the viewport.
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return undefined;
    const nodes = Array.from(document.querySelectorAll("[data-reveal]"));
    nodes.forEach((node) => node.classList.add("revealPending"));
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("revealIn");
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.16, rootMargin: "0px 0px -40px 0px" });
    nodes.forEach((node) => observer.observe(node));
    return () => observer.disconnect();
  }, []);

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
      <header className={navScrolled ? "lpNav lpNavScrolled" : "lpNav"}>
        <div className="lpWrap lpNavInner">
          <a className="wordmark" href="#play" aria-label="Read the World home">
            read the world<span>.</span>
          </a>
          <nav aria-label="Primary">
            <a href="#how">How it works</a>
            <a href="#rooms">Rooms</a>
            <a href="#party">Party mode</a>
            <a href="#world">The World</a>
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
            Three shared questions a day. Answer for yourself, then predict how
            everyone else answers. Win by being the best at reading the room.
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
            <div className="heroSwap" key={step === "answer" ? currentQuestion?.qid ?? "loading" : "gate"}>
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
            </div>
          </section>
          {worldQuestions.length > 0 && liveCount > 0 ? (
            <div className="liveCount">{liveCount.toLocaleString()} people have answered today</div>
          ) : null}
        </div>
      </section>

      <section className="lpBand" id="how">
        <div className="lpWrap lpSection">
          <div className="sectionHead" data-reveal>
            <div className="eyebrow">The daily ritual</div>
            <h2 className="serif">
              Three questions a day.
              <br />
              One shared reveal.
            </h2>
          </div>
          <div className="ritualGrid" data-reveal data-reveal-delay="1">
            <article>
              <b className="serif">01</b>
              <h3 className="serif">Answer</h3>
              <p>Pick your side on each question. It stays private.</p>
            </article>
            <article>
              <b className="serif">02</b>
              <h3 className="serif">Predict</h3>
              <p>Guess what share of the room agrees with you. This is the real game.</p>
            </article>
            <article>
              <b className="serif">03</b>
              <h3 className="serif">Score</h3>
              <p>Tomorrow the split reveals. The sharpest reads take the points.</p>
            </article>
          </div>
        </div>
      </section>

      <section className="lpWrap lpSection lpCols" id="rooms">
        <div data-reveal>
          <div className="eyebrow clay">First, your people &middot; Rooms</div>
          <h2 className="serif">Made for the people you know best.</h2>
          <p>
            A room is your crew: friends, family, teammates. Same three
            questions, everyone predicts everyone, reveal the next morning.
            Start one in seconds, invite with a link.
          </p>
        </div>
        <div className="lpRoomStack" data-reveal data-reveal-delay="1" aria-label="Example rooms">
          <div className="lpRoomRow">
            <span className="lpRoomAvatar" data-tone="blue">C</span>
            <span className="lpRoomMeta">
              <strong className="serif">The Crew</strong>
              <small>7 players &middot; you&apos;re #2 on the board</small>
            </span>
            <span className="lpRoomPill filled">Play today&apos;s 3</span>
          </div>
          <div className="lpRoomRow">
            <span className="lpRoomAvatar" data-tone="clay">F</span>
            <span className="lpRoomMeta">
              <strong className="serif">Family</strong>
              <small>4 players &middot; reveal tomorrow</small>
            </span>
            <span className="lpRoomPill">Locked in</span>
          </div>
        </div>
      </section>

      <section className="lpBand">
        <div className="lpWrap lpSection">
          <div className="sectionHead" data-reveal>
            <div className="eyebrow">Every room, your rules</div>
            <h2 className="serif">Set the spice level.</h2>
          </div>
          <div className="spiceGrid" data-reveal data-reveal-delay="1">
            <article className="spiceCard">
              <div className="eyebrow">Work-safe</div>
              <h3 className="serif">Team-ready.</h3>
              <p>Nothing you&apos;d flinch at in standup. Built for the office room.</p>
            </article>
            <article className="spiceCard">
              <div className="eyebrow clay">Everyday</div>
              <h3 className="serif">The full mix.</h3>
              <p>Confessions, ethical dilemmas, would-you-rathers. Where most rooms live.</p>
            </article>
            <article className="spiceCard spiceDark">
              <div className="eyebrow onDark">After Dark</div>
              <h3 className="serif">For groups that like it spicy.</h3>
              <p>Adults only, words only. Your group chat&apos;s natural habitat.</p>
            </article>
          </div>
          <p className="spiceFoot" data-reveal data-reveal-delay="2">
            Every room picks its own spice level and topics. The office room
            and the group chat never have to meet.
          </p>
        </div>
      </section>

      <section className="lpWrap lpSection lpCols" id="score">
        <div data-reveal>
          <div className="eyebrow clay">Prove it &middot; Your Read Score</div>
          <h2 className="serif">It&apos;s not about being right. It&apos;s about reading the room.</h2>
          <p>
            Points for accurate predictions, not popular opinions. Every room
            has a leaderboard. Every reveal moves it.
          </p>
        </div>
        <div className="leaderboard" data-reveal data-reveal-delay="1">
          <div className="leaderHead">The Crew &middot; Leaderboard</div>
          <div className="me">
            <span>1</span>
            <strong>You</strong>
            <b className="serif"><CountUp value={1840} duration={900} /></b>
          </div>
          <div>
            <span>2</span>
            <strong>Maya</strong>
            <b className="serif"><CountUp value={1792} duration={900} /></b>
          </div>
          <div>
            <span>3</span>
            <strong>Diego</strong>
            <b className="serif"><CountUp value={1710} duration={900} /></b>
          </div>
          <div>
            <span>4</span>
            <strong>Priya</strong>
            <b className="serif"><CountUp value={1655} duration={900} /></b>
          </div>
        </div>
      </section>

      <section className="lpWrap lpSection lpCols">
        <div data-reveal>
          <div className="eyebrow clay">Make it yours &middot; Custom questions</div>
          <h2 className="serif">The question you&apos;ve been dying to ask.</h2>
          <p>
            Drop your own question into the pool. It shows up in a coming
            day&apos;s three, with your name on the reveal.
          </p>
        </div>
        <div className="lpPoolColumn" data-reveal data-reveal-delay="1">
          <div className="lpPoolCard">
            <div className="lpPoolTop">
              <span>From the pool</span>
              <span>By Maya</span>
            </div>
            <h3 className="serif">Would the group ever actually move abroad?</h3>
          </div>
          <div className="lpPoolAdd">
            <span>+ Add your own question</span>
            <span>4 in the pool</span>
          </div>
        </div>
      </section>

      <section className="partyBand" id="party">
        <div className="lpWrap lpSection lpCols">
          <div data-reveal>
            <div className="eyebrow onDark">Then, the table &middot; Party mode</div>
            <h2 className="serif">Pass the phone.</h2>
            <p>
              One phone, no accounts, instant reveals. Take turns predicting
              the table. Sharpest read wins.
            </p>
          </div>
          <div className="partyDeck" data-reveal data-reveal-delay="1" aria-label="Sample party mode question deck">
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

      <section className="lpWrap lpSection worldSection" id="world">
        <div className="sectionHead" data-reveal>
          <div className="eyebrow blue">Finally, the World</div>
          <h2 className="serif">Then there&apos;s the whole world.</h2>
          <p>
            One room with everyone in it. Answering is open now. Predicting
            unlocks the moment {worldGoal.toLocaleString()} of us are playing.
          </p>
        </div>
        <div className="worldCounter" data-reveal data-reveal-delay="1">
          <div className="worldCounterTop">
            <span>
              <b className="serif"><CountUp value={worldMembers} /></b> / {worldGoal.toLocaleString()} players
            </span>
            <span className="worldLive">
              <i />Live &middot; {Math.min(100, Math.round((worldMembers / worldGoal) * 100))}% there
            </span>
          </div>
          <div className="worldBar">
            <div
              className="worldBarFill"
              style={{ width: `${Math.min(100, (worldMembers / worldGoal) * 100)}%` }}
            />
          </div>
          <div className="worldCounterBottom">
            <span>
              {Math.max(0, worldGoal - worldMembers).toLocaleString()} players to go.
              Every friend you bring counts.
            </span>
            <a className="worldButton" href="#play">
              Claim your spot <span aria-hidden="true">→</span>
            </a>
          </div>
        </div>
      </section>

      <section className="lpBand">
        <div className="lpWrap lpSection">
          <div className="sectionHead" data-reveal>
            <div className="eyebrow">Every topic, every day</div>
            <h2 className="serif">Questions worth arguing about.</h2>
          </div>
          <div className="sampleGrid" data-reveal data-reveal-delay="1">
            {argueQuestions.map((question) => (
              <article key={question.id}>
                <div className="eyebrow clay">{question.category}</div>
                <h3 className="serif">{question.prompt}</h3>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="faq">
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

      <section className="downloadBand" id="downloads">
        <div className="lpWrap lpSection lpCols downloadSection">
          <div data-reveal>
            <div className="eyebrow clay">Take it with you</div>
            <h2 className="serif">The daily read, in your pocket.</h2>
            <p>
              Native apps are coming. Until then, it all runs in your browser.
              No download needed.
            </p>
            <a className="darkButton downloadWebButton" href="#play">
              Play today&apos;s questions <span aria-hidden="true">→</span>
            </a>
          </div>
          <div className="downloadCards" data-reveal data-reveal-delay="1" aria-label="Upcoming app downloads">
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

      <footer className="lpWrap lpSection footerCta">
        <h2 className="serif">How well do you really read others?</h2>
        <p>Today&apos;s three are waiting. Start a room and find out. Free, every day.</p>
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
