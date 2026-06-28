import { ImageResponse } from "next/og";
import { fallbackShareCard, readShareCard } from "@/lib/shareCards";

type ShareImageContext = {
  params: Promise<{ code: string }>;
};

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const size = {
  width: 1200,
  height: 630,
};

export async function GET(_request: Request, { params }: ShareImageContext) {
  const { code } = await params;
  const card = await readShareCard(code).catch(() => null);
  const shareCard = card ?? fallbackShareCard;
  const promptSize = shareCard.prompt.length > 96 ? 56 : shareCard.prompt.length > 72 ? 64 : 72;
  const kicker = [
    shareCard.eyebrow.toUpperCase(),
    shareCard.category.toUpperCase(),
    shareCard.dateLabel,
  ].filter(Boolean).join(" · ");

  const response = new ImageResponse(
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
          padding: "54px 66px",
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
            daily read
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", maxWidth: 1000 }}>
          <div
            style={{
              color: "#9E9587",
              fontSize: 22,
              fontWeight: 700,
              letterSpacing: 4.8,
              textTransform: "uppercase",
              marginBottom: 24,
            }}
          >
            {kicker}
          </div>
          <div
            style={{
              color: "#28241D",
              display: "flex",
              fontFamily: "Georgia",
              fontSize: promptSize,
              fontWeight: 500,
              letterSpacing: 0,
              lineHeight: 1.05,
              maxWidth: 1040,
            }}
          >
            {shareCard.prompt}
          </div>
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
    size,
  );
  response.headers.set("Cache-Control", "public, max-age=300, s-maxage=300");
  return response;
}
