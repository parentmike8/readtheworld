import { ImageResponse } from "next/og";
import { readWorldToday } from "@/lib/worldToday";

// Fetched per send by link-preview bots (iMessage, Slack, X); always render
// the current world day rather than a build-time snapshot.
export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const alt = "Today's three world questions on Read the World";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default async function Image() {
  const today = await readWorldToday();
  const kicker = ["TODAY'S WORLD QUESTIONS", today.dateLabel].filter(Boolean).join(" · ");
  const longest = Math.max(...today.questions.map((question) => question.prompt.length));
  const promptSize = longest > 72 ? 34 : longest > 52 ? 40 : 44;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#F4EFE6",
          color: "#27241D",
          padding: "50px 66px",
          fontFamily: "Arial",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div
            style={{
              display: "flex",
              alignItems: "baseline",
              fontSize: 36,
              fontWeight: 700,
              letterSpacing: -0.2,
            }}
          >
            read the world<span style={{ color: "#B7643F" }}>.</span>
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              color: "#8C8577",
              fontSize: 20,
              fontWeight: 700,
              letterSpacing: 2.8,
              textTransform: "uppercase",
            }}
          >
            {kicker}
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 26 }}>
          {today.questions.map((question, index) => (
            <div
              key={index}
              style={{ display: "flex", alignItems: "center", gap: 26, maxWidth: 1068 }}
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  width: 46,
                  height: 46,
                  borderRadius: 999,
                  border: "2px solid #D9D2C3",
                  color: "#8C8577",
                  fontSize: 22,
                  fontWeight: 700,
                  flexShrink: 0,
                }}
              >
                {index + 1}
              </div>
              <div
                style={{
                  color: "#28241D",
                  display: "flex",
                  fontFamily: "Georgia",
                  fontSize: promptSize,
                  fontWeight: 500,
                  lineHeight: 1.08,
                }}
              >
                {question.prompt}
              </div>
            </div>
          ))}
        </div>

        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div
            style={{
              color: "#5C584F",
              fontSize: 28,
              fontWeight: 700,
            }}
          >
            Answer for yourself. Predict the world.
          </div>
          <div
            style={{
              background: "#2F55A4",
              borderRadius: 999,
              color: "#FFFFFF",
              fontSize: 24,
              fontWeight: 700,
              padding: "15px 24px",
            }}
          >
            Play today
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
