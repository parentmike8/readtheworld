import { connection } from "next/server";
import LandingPage from "./LandingPage";
import { readWorldToday } from "@/lib/worldToday";

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": "https://readtheworld.today/#organization",
      name: "Read the World",
      url: "https://readtheworld.today/",
      logo: "https://readtheworld.today/icon.png",
      email: "mike@readtheworld.today",
    },
    {
      "@type": "WebSite",
      "@id": "https://readtheworld.today/#website",
      name: "Read the World",
      url: "https://readtheworld.today/",
      description:
        "A daily social prediction game for friends, families, teams, and the world.",
      publisher: { "@id": "https://readtheworld.today/#organization" },
      inLanguage: "en",
    },
    {
      "@type": "SoftwareApplication",
      "@id": "https://readtheworld.today/#app",
      name: "Read the World",
      url: "https://readtheworld.today/",
      applicationCategory: "GameApplication",
      applicationSubCategory: "Social prediction game",
      operatingSystem: "Web",
      isAccessibleForFree: true,
      description:
        "Answer three daily questions privately, predict how your room will answer, and score how accurately you read the group.",
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
      },
      provider: { "@id": "https://readtheworld.today/#organization" },
    },
  ],
};

export default async function Home() {
  // The World rolls over daily, so render from the current request instead of
  // freezing a question set into the deployment artifact.
  await connection();
  const worldToday = await readWorldToday();

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c"),
        }}
      />
      <LandingPage initialWorld={worldToday} />
    </>
  );
}
