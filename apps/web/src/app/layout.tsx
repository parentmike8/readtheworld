import type { Metadata } from "next";
import { Hanken_Grotesk, IBM_Plex_Mono, Newsreader } from "next/font/google";
import "./globals.css";

const hanken = Hanken_Grotesk({
  variable: "--font-hanken",
  subsets: ["latin"],
});

const newsreader = Newsreader({
  variable: "--font-newsreader",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const plexMono = IBM_Plex_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://readtheworld.today"),
  title: {
    default: "Read the World",
    template: "%s · Read the World",
  },
  description:
    "A daily game of public opinion. Answer for yourself, predict the world, and build your Read Score.",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "Read the World",
    description:
      "One shared question a day. Answer for yourself, then predict how the world will answer.",
    url: "https://readtheworld.today",
    siteName: "Read the World",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "Read the World",
    description:
      "One shared question a day. Answer for yourself, then predict how the world will answer.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${hanken.variable} ${newsreader.variable} ${plexMono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
