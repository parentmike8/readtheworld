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
import { useEffect, useMemo, useRef, useState } from "react";
import { activateClientAppCheck } from "@/lib/appCheck";

const faqs = [
  [
    "Is it the same question for everyone?",
    "Yes. Every player worldwide gets the same question each day, so you are always reading the same global crowd.",
  ],
  [
    "Why don't results show right away?",
    "Results arrive the next day, when the new question drops. You commit your read before you see how it landed.",
  ],
  [
    "How is my score calculated?",
    "Your Read Score rewards how close your prediction was to the actual global result, not whether you agreed with the majority.",
  ],
  [
    "Is it free?",
    "Yes. One question a day, free. Create an account to save your streak, track your score, and compare with friends.",
  ],
];

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const appBaseUrl = "https://app.readtheworld.today";

type LiveQuestion = {
  id: string;
  category: string;
  prompt: string;
  options: Array<{ id: string; label: string }>;
};

type PublicQuestion = Pick<LiveQuestion, "id" | "category" | "prompt">;

function hasFirebaseConfig() {
  return Object.values(firebaseConfig).every(Boolean);
}

function predictionWord(value: number) {
  if (value <= 12) return "Almost no one, you think";
  if (value <= 35) return "You're betting minority";
  if (value <= 45) return "A little under half";
  if (value <= 55) return "Split down the middle";
  if (value <= 70) return "A clear majority";
  if (value <= 88) return "Most of the world";
  return "Nearly everyone";
}

export default function Home() {
  const [step, setStep] = useState<"answer" | "predict" | "gate">("answer");
  const [answerId, setAnswerId] = useState<string | null>(null);
  const [prediction, setPrediction] = useState(50);
  const [dragging, setDragging] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [footerEmail, setFooterEmail] = useState("");
  const [submitError, setSubmitError] = useState("");
  const [submitting, setSubmitting] = useState<"" | "gate">("");
  const [openFaq, setOpenFaq] = useState(0);
  const [liveQuestion, setLiveQuestion] = useState<LiveQuestion | null>(null);
  const [recentQuestions, setRecentQuestions] = useState<PublicQuestion[]>([]);
  const [liveCount, setLiveCount] = useState(0);
  const [user, setUser] = useState<User | null>(null);
  const [todayAnswer, setTodayAnswer] = useState<{
    questionId: string;
    selectedOptionId: string;
    predictedShare: number;
  } | null>(null);
  const trackRef = useRef<HTMLDivElement | null>(null);
  const app = useMemo<FirebaseApp | null>(() => {
    if (!hasFirebaseConfig()) return null;
    const firebaseApp = getApps()[0] ?? initializeApp(firebaseConfig);
    activateClientAppCheck(firebaseApp);
    return firebaseApp;
  }, []);
  const firestore = useMemo(() => (app ? getFirestore(app) : null), [app]);
  const auth = useMemo(() => (app ? getAuth(app) : null), [app]);
  const functions = useMemo(() => (app ? getFunctions(app, "us-central1") : null), [app]);

  useEffect(() => {
    if (!firestore) return undefined;
    const liveQuery = query(
      collection(firestore, "questions"),
      where("status", "==", "live"),
      orderBy("publishAt", "desc"),
      limit(1),
    );
    return onSnapshot(liveQuery, (snapshot) => {
      const first = snapshot.docs[0];
      if (!first) {
        setLiveQuestion(null);
        setLiveCount(0);
        return;
      }
      const data = first.data();
      const options = Array.isArray(data.options)
        ? data.options
            .map((option) => ({
              id: String(option?.id ?? ""),
              label: String(option?.label ?? ""),
            }))
            .filter((option) => option.id && option.label)
        : [];
      setLiveQuestion({
        id: first.id,
        category: String(data.category ?? "Today"),
        prompt: String(data.prompt ?? "Loading today's question..."),
        options,
      });
    });
  }, [firestore]);

  useEffect(() => {
    if (!firestore) return undefined;
    const recentQuery = query(
      collection(firestore, "dailyResults"),
      where("status", "==", "closed"),
      orderBy("closedAt", "desc"),
      limit(6),
    );
    return onSnapshot(recentQuery, (snapshot) => {
      setRecentQuestions(snapshot.docs.map((docSnap) => {
        const data = docSnap.data();
        return {
          id: docSnap.id,
          category: String(data.category ?? "Daily read"),
          prompt: String(data.prompt ?? ""),
        };
      }).filter((question) => question.prompt.length > 0));
    });
  }, [firestore]);

  useEffect(() => {
    if (!firestore || !liveQuestion) return undefined;
    return onSnapshot(doc(firestore, "questionCounters", liveQuestion.id), (snapshot) => {
      const total = Number(snapshot.data()?.total ?? 0);
      setLiveCount(Number.isFinite(total) ? total : 0);
    });
  }, [firestore, liveQuestion]);

  useEffect(() => {
    if (!auth) return undefined;
    return onAuthStateChanged(auth, (nextUser) => {
      setUser(nextUser);
      if (nextUser?.email) setEmail((current) => current || nextUser.email || "");
    });
  }, [auth]);

  useEffect(() => {
    if (!firestore || !user || !liveQuestion) return undefined;
    return onSnapshot(
      doc(firestore, "users", user.uid, "answers", liveQuestion.id),
      (snapshot) => {
        const data = snapshot.data();
        if (!snapshot.exists() || !data) {
          setTodayAnswer(null);
          return;
        }
        const predictedShare = Number(data.predictedShare ?? 0);
        setTodayAnswer({
          questionId: liveQuestion.id,
          selectedOptionId: String(data.selectedOptionId ?? ""),
          predictedShare: Number.isFinite(predictedShare) ? predictedShare : 0,
        });
      },
    );
  }, [firestore, user, liveQuestion]);

  const predictPrompt = useMemo(
    () => `What share of people also answered "${selectedAnswerLabel(liveQuestion, answerId) ?? "Yes"}"?`,
    [answerId, liveQuestion],
  );
  const playedToday = Boolean(user && liveQuestion && todayAnswer?.questionId === liveQuestion.id && todayAnswer.selectedOptionId);
  const navCtaLabel = !user ? "Log in" : playedToday ? "Enter app" : "Play today";
  const submittedAnswerLabel = selectedAnswerLabel(liveQuestion, todayAnswer?.selectedOptionId ?? null);

  function setPredictionFromPointer(clientX: number) {
    const element = trackRef.current;
    if (!element) return;
    const rect = element.getBoundingClientRect();
    const next = Math.round(((clientX - rect.left) / rect.width) * 100);
    setPrediction(Math.max(0, Math.min(100, next)));
  }

  function pick(next: string) {
    setAnswerId(next);
    setStep("predict");
    setSubmitError("");
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

  async function createAppHandoff(targetRoute: string, pending?: {
    questionId: string;
    selectedOptionId: string;
    predictedShare: number;
  }) {
    if (!functions) return `${appBaseUrl}${targetRoute}`;
    const callable = httpsCallable(functions, "createAuthHandoff");
    const result = await callable({
      targetRoute,
      ...(pending ?? {}),
    });
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
    if (!liveQuestion || !answerId) {
      setSubmitError("Choose an answer first.");
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
      const destination = await createAppHandoff("/today/predict", {
        questionId: liveQuestion.id,
        selectedOptionId: answerId,
        predictedShare: prediction,
      });
      window.location.href = destination;
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
              onClick={() => enterApp(!user ? "/auth" : playedToday ? "/history" : "/today")}
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
            One shared question a day. Answer for yourself, then predict how the
            world will answer. The closer your prediction, the higher your score.
          </p>
        </div>

        <div className="liveCardColumn">
          <section className="liveCard" aria-label="Live question">
            <div className="questionTop">
              <span>Today{liveQuestion ? ` · ${liveQuestion.category}` : ""}</span>
              <span className="liveDot"><i />Live</span>
            </div>
            {step === "predict" ? (
              <div className="predictQuestionHeader">
                <p>{liveQuestion?.prompt ?? "Loading today's question..."}</p>
                <h2 className="serif">{predictPrompt}</h2>
              </div>
            ) : (
              <h2 className="serif">{liveQuestion?.prompt ?? "Loading today's question..."}</h2>
            )}

            {playedToday ? (
              <div className="submittedState">
                <div>
                  <span>{"\u2713"}</span>
                  <strong>Your read is locked.</strong>
                </div>
                <p>
                  You answered {submittedAnswerLabel ?? "today"} and predicted {todayAnswer?.predictedShare ?? "--"}%.
                  Come back after the reveal to see how close you were.
                </p>
                <button className="blueButton" onClick={() => enterApp("/history")} disabled={submitting === "gate"}>
                  Enter app {"\u2192"}
                </button>
              </div>
            ) : step === "answer" ? (
              <div className="answerStep">
                <p>First, where do you stand?</p>
                {(liveQuestion?.options ?? []).map((option) => (
                  <button
                    key={option.id}
                    className={answerId === option.id ? "selected" : ""}
                    onClick={() => pick(option.id)}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            ) : null}

            {step === "predict" ? (
              <div className="predictStep">
                <div className="predictNumber">
                  <span className="serif">{prediction}</span>
                  <small className="serif">%</small>
                </div>
                <div className="predictWord">{predictionWord(prediction)}</div>
                <div
                  ref={trackRef}
                  className="lpSlider"
                  onPointerDown={(event) => {
                    event.currentTarget.setPointerCapture(event.pointerId);
                    setDragging(true);
                    setPredictionFromPointer(event.clientX);
                  }}
                  onPointerMove={(event) => {
                    if (dragging) setPredictionFromPointer(event.clientX);
                  }}
                  onPointerUp={() => setDragging(false)}
                >
                  <div className="lpSliderTrack">
                    <div className="lpSliderFill" style={{ width: `${prediction}%` }} />
                    <div className="lpSliderPin" style={{ left: `${prediction}%` }} />
                  </div>
                </div>
                <button className="blueButton" onClick={() => setStep("gate")}>
                  Lock it in {"\u2192"}
                </button>
                <button className="ghostButton" onClick={() => setStep("answer")}>
                  {"\u2190"} Change my answer
                </button>
              </div>
            ) : null}

            {step === "gate" ? (
              <div className="gateStep">
                <div className="gateBox">
                  <div>
                    <span>Your answer &middot; {selectedAnswerLabel(liveQuestion, answerId)}</span>
                    <span>Your read &middot; {prediction}%</span>
                  </div>
                  <p>
                    The world&apos;s answer appears tomorrow. Sign in or create a free account
                    to save this read, see your past answers, and track your score.
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
                <button className="ghostButton left" onClick={() => setStep("predict")}>
                  {"\u2190"} Change my prediction
                </button>
              </div>
            ) : null}
          </section>
          {liveQuestion ? (
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
              Play today&apos;s question <span aria-hidden="true">→</span>
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
          {recentQuestions.length > 0 ? recentQuestions.map((question) => (
            <article key={question.id}>
              <div className="eyebrow clay">{question.category}</div>
              <h3 className="serif">{question.prompt}</h3>
            </article>
          )) : (
            <article>
              <div className="eyebrow clay">Live archive</div>
              <h3 className="serif">Loading recent questions...</h3>
            </article>
          )}
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
        <h2 className="serif">Today&apos;s question is waiting.</h2>
        <p>Join the daily read. Free, one question a day.</p>
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

function selectedAnswerLabel(question: LiveQuestion | null, optionId: string | null) {
  if (!question || !optionId) return null;
  return question.options.find((option) => option.id === optionId)?.label ?? optionId;
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
