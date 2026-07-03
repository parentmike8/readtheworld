// Same card as the OG image so twitter:image is set explicitly (some
// scrapers will not fall back to og:image for large-card previews).
// Segment config must be literal here: Next rejects re-exported config.
export { default } from "./opengraph-image";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const alt = "Today's three world questions on Read the World";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";
