import type { Metadata } from "next";
import { fallbackShareCard, readShareCard } from "@/lib/shareCards";

type SharePageProps = {
  params: Promise<{ code: string }>;
};

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function generateMetadata({ params }: SharePageProps): Promise<Metadata> {
  const { code } = await params;
  const card = await readShareCard(code).catch(() => null);
  const shareCard = card ?? fallbackShareCard;
  const title = shareCard.title === "Read the World"
    ? "Read the World"
    : `${shareCard.title} · Read the World`;
  const imageUrl = `/share/${encodeURIComponent(code)}/image`;
  const url = `/share/${encodeURIComponent(code)}`;

  return {
    title: { absolute: title },
    description: shareCard.description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description: shareCard.description,
      url,
      siteName: "Read the World",
      type: "website",
      images: [
        {
          url: imageUrl,
          width: 1200,
          height: 630,
          alt: `Read the World question: ${shareCard.prompt}`,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description: shareCard.description,
      images: [imageUrl],
    },
  };
}

export default async function SharePage({ params }: SharePageProps) {
  const { code } = await params;
  const card = await readShareCard(code).catch(() => null);
  const shareCard = card ?? fallbackShareCard;
  const destination = card?.destinationUrl ?? fallbackShareCard.destinationUrl;

  return (
    <main className="shareRedirectPage">
      <script
        dangerouslySetInnerHTML={{
          __html: `window.location.replace(${JSON.stringify(destination)});`,
        }}
      />
      <section>
        <div className="shareRedirectMark">read<span>.</span></div>
        <p>{shareCard.eyebrow}</p>
        <h1>{shareCard.prompt}</h1>
        <a href={destination}>Open Read the World</a>
      </section>
    </main>
  );
}
