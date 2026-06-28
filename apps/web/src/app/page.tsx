"use client";

import { FirebaseError, getApps, initializeApp, type FirebaseApp } from "firebase/app";
import { getFunctions, httpsCallable } from "firebase/functions";
import { useEffect, useMemo, useRef, useState } from "react";

const leaders = [
  ["1", "You", "1,840"],
  ["2", "Dana K.", "1,792"],
  ["3", "Marcus R.", "1,710"],
  ["4", "Priya S.", "1,655"],
];

const samples = [
  ["TECHNOLOGY", "Should AI-generated content always be labelled?"],
  ["MONEY", "Would you take a 20% pay cut for a four-day week?"],
  ["SCIENCE", "Is there intelligent life elsewhere in the universe?"],
  ["CULTURE", "Are physical books better than e-books?"],
  ["PHILOSOPHY", "Is it ever okay to lie to protect someone's feelings?"],
  ["RELATIONSHIPS", "Should you stay friends with an ex?"],
];

const faqs = [
  [
    "Is it the same question for everyone?",
    "Yes. Every player worldwide gets the same question each day, so you are always reading the same global crowd.",
  ],
  [
    "Why don't results show right away?",
    "Results unlock the next day, when the new question drops. The delay keeps the daily ritual honest: you commit your read before you see how it landed.",
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
  const [answer, setAnswer] = useState<"Yes" | "No" | null>(null);
  const [prediction, setPrediction] = useState(50);
  const [dragging, setDragging] = useState(false);
  const [email, setEmail] = useState("");
  const [footerEmail, setFooterEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [footerSubmitted, setFooterSubmitted] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [submitting, setSubmitting] = useState<"" | "gate" | "footer">("");
  const [openFaq, setOpenFaq] = useState(0);
  const [liveCount, setLiveCount] = useState(184927);
  const trackRef = useRef<HTMLDivElement | null>(null);
  const app = useMemo<FirebaseApp | null>(() => {
    if (!hasFirebaseConfig()) return null;
    return getApps()[0] ?? initializeApp(firebaseConfig);
  }, []);
  const functions = useMemo(() => (app ? getFunctions(app, "us-central1") : null), [app]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      setLiveCount((value) => value + Math.floor(Math.random() * 7) + 1);
    }, 1500);
    return () => window.clearInterval(interval);
  }, []);

  const predictPrompt = useMemo(
    () => `What share of people also answered "${answer ?? "Yes"}"?`,
    [answer],
  );

  function setPredictionFromPointer(clientX: number) {
    const element = trackRef.current;
    if (!element) return;
    const rect = element.getBoundingClientRect();
    const next = Math.round(((clientX - rect.left) / rect.width) * 100);
    setPrediction(Math.max(0, Math.min(100, next)));
  }

  function pick(next: "Yes" | "No") {
    setAnswer(next);
    setStep("predict");
    setSubmitted(false);
    setSubmitError("");
  }

  async function submitWaitlist(nextEmail: string, source: "landing_gate" | "landing_footer") {
    const normalizedEmail = nextEmail.trim();
    if (!normalizedEmail.includes("@")) {
      setSubmitError("Enter a valid email address.");
      return false;
    }
    if (!functions) {
      setSubmitError("");
      return true;
    }

    setSubmitError("");
    setSubmitting(source === "landing_gate" ? "gate" : "footer");
    try {
      const callable = httpsCallable(functions, "joinWaitlist");
      await callable({
        email: normalizedEmail,
        source,
        answer,
        predictedShare: prediction,
      });
      return true;
    } catch (error) {
      const message = error instanceof FirebaseError ? error.message : String(error);
      setSubmitError(message);
      return false;
    } finally {
      setSubmitting("");
    }
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
            <a className="lpHideMobile" href="https://app.readtheworld.today/auth">
              Log in
            </a>
            <a className="darkButton" href="#play">
              Play today {"\u2192"}
            </a>
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
            world will answer. The sharper your read, the higher your score.
          </p>
          <div className="lpStats" aria-label="Product stats">
            <div>
              <strong className="serif">2.4M</strong>
              <span>Answers / day</span>
            </div>
            <div>
              <strong className="serif">190</strong>
              <span>Countries</span>
            </div>
            <div>
              <strong className="serif">11</strong>
              <span>Categories</span>
            </div>
          </div>
        </div>

        <div className="liveCardColumn">
          <section className="liveCard" aria-label="Live sample question">
            <div className="questionTop">
              <span>Today &middot; Philosophy</span>
              <span className="liveDot"><i />Live</span>
            </div>
            <h2 className="serif">Would you want to know the exact date you&apos;ll die?</h2>

            {step === "answer" ? (
              <div className="answerStep">
                <p>First, where do you stand?</p>
                <button className={answer === "Yes" ? "selected" : ""} onClick={() => pick("Yes")}>
                  Yes
                </button>
                <button className={answer === "No" ? "selected" : ""} onClick={() => pick("No")}>
                  No
                </button>
              </div>
            ) : null}

            {step === "predict" ? (
              <div className="predictStep">
                <p>{predictPrompt}</p>
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
                    <span>Your answer &middot; {answer}</span>
                    <span>Your read &middot; {prediction}%</span>
                  </div>
                  <p>
                    The world&apos;s answer unlocks tomorrow. Create a free account to
                    lock your prediction and start your streak.
                  </p>
                </div>
                {!submitted ? (
                  <>
                    <div className="gateForm">
                      <input
                        value={email}
                        onChange={(event) => setEmail(event.target.value)}
                        placeholder="you@email.com"
                        type="email"
                      />
                      <button
                        disabled={submitting === "gate"}
                        onClick={async () => {
                          const ok = await submitWaitlist(email, "landing_gate");
                          if (ok) setSubmitted(true);
                        }}
                      >
                        {submitting === "gate" ? "Saving..." : "Lock it in"}
                      </button>
                    </div>
                    {submitError ? <p className="formError">{submitError}</p> : null}
                    <button className="ghostButton left" onClick={() => setStep("predict")}>
                      {"\u2190"} Change my prediction
                    </button>
                  </>
                ) : (
                  <div className="successBox">
                    <span>{"\u2713"}</span>
                    <p>You&apos;re in. Come back tomorrow for the reveal and your first Read Score.</p>
                  </div>
                )}
              </div>
            ) : null}
          </section>
          <div className="liveCount">{liveCount.toLocaleString()} people have answered today</div>
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
              <p>Take your own side on today&apos;s question. It stays private {"\u2014"} it is just your input.</p>
            </article>
            <article>
              <b className="serif">02</b>
              <h3 className="serif">Predict</h3>
              <p>Guess what share of the world answered the same way. This is the real game.</p>
            </article>
            <article>
              <b className="serif">03</b>
              <h3 className="serif">Reveal</h3>
              <p>Tomorrow, see how the world really answered and how sharp your read was.</p>
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
          {leaders.map(([rank, name, score], index) => (
            <div key={rank} className={index === 0 ? "me" : ""}>
              <span>{rank}</span>
              <strong>{name}</strong>
              <b className="serif">{score}</b>
            </div>
          ))}
        </div>
      </section>

      <section className="partyBand" id="party">
        <div className="lpWrap lpSection lpCols">
          <div>
            <div className="eyebrow onDark">Party mode</div>
            <h2 className="serif">Read the room, together.</h2>
            <p>
              Throw it on a screen and run through past questions as a group.
              Call each one out loud, then reveal how the world really answered.
              No scores {"\u2014"} just great debate.
            </p>
          </div>
          <div className="partyCard">
            <div className="eyebrow onDark">Culture</div>
            <h3 className="serif">Is it rude to keep your phone on the table at dinner?</h3>
            <div className="partyResult">
              <span className="yesFill" />
              <b>YES 62%</b>
              <em>NO</em>
            </div>
          </div>
        </div>
      </section>

      <section className="lpWrap lpSection">
        <div className="sectionHead">
          <div className="eyebrow">Every topic, every day</div>
          <h2 className="serif">Questions worth arguing about.</h2>
        </div>
        <div className="sampleGrid">
          {samples.map(([category, question]) => (
            <article key={question}>
              <div className="eyebrow clay">{category}</div>
              <h3 className="serif">{question}</h3>
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
        <h2 className="serif">Today&apos;s question is waiting.</h2>
        <p>Join the daily read. Free, one question a day.</p>
        <form
          onSubmit={async (event) => {
            event.preventDefault();
            const ok = await submitWaitlist(footerEmail, "landing_footer");
            if (ok) setFooterSubmitted(true);
          }}
        >
          <input
            value={footerEmail}
            onChange={(event) => setFooterEmail(event.target.value)}
            placeholder="you@email.com"
            type="email"
          />
          <button type="submit" disabled={submitting === "footer"}>
            {submitting === "footer" ? "Saving..." : footerSubmitted ? "You're in" : "Get started"}
          </button>
        </form>
        {footerSubmitted ? (
          <div className="footerSuccess">You&apos;re in. We&apos;ll send your invite when beta opens.</div>
        ) : submitError ? (
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
