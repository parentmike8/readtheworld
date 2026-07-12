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
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/icon.png", type: "image/png", sizes: "512x512" },
    ],
    apple: [{ url: "/apple-icon.png", type: "image/png", sizes: "180x180" }],
  },
  openGraph: {
    title: "Read the World",
    description:
      "Three shared questions a day. Answer privately, predict how the group will answer, and see how close your read was.",
    url: "https://readtheworld.today",
    siteName: "Read the World",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Read the World",
    description:
      "Three shared questions a day. Answer privately, predict how the group will answer, and see how close your read was.",
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
