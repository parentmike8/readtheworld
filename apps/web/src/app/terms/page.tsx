import type { Metadata } from "next";
import { LegalPage } from "../LegalPage";

export const metadata: Metadata = {
  title: "Terms",
  description: "Read the World terms of use.",
  alternates: {
    canonical: "/terms",
  },
};

const sections = [
  {
    title: "Using Read the World",
    body: [
      "Read the World is a daily social prediction game. You answer questions, predict how rooms or groups will answer, and compare results when reveals and scoring are available.",
      "You must be at least 13 years old to use the service. You are responsible for your account, your device, and the activity that happens through your account.",
    ],
  },
  {
    title: "Accounts",
    body: [
      "You agree to provide accurate account information and keep your sign-in credentials secure. If you believe your account has been compromised, contact us at mike@readtheworld.today.",
      "We may suspend or terminate accounts that abuse the service, interfere with other users, violate these terms, or create legal, security, or operational risk.",
    ],
  },
  {
    title: "Your content and activity",
    body: [
      "You are responsible for the feedback, room names, questions, messages, answers, predictions, reactions, and other content you submit.",
      "You grant us permission to host, store, process, display, and use that content as needed to provide, improve, promote, and protect the service.",
      "Custom questions are visible only to authenticated members of the private, invite-only room where they were submitted. Each live custom question identifies the member who submitted it. Read the World does not provide a public custom-question feed, anonymous chat, or discovery of questions from strangers.",
      "We have zero tolerance for content that is unlawful, threatening, abusive, harassing, hateful, sexually exploitative, invasive of another person's privacy, misleading, spam, or otherwise harmful. Do not submit it.",
      "Room members may report a custom question, which removes it from the room immediately. Room creators may block a member from submitting additional custom questions. We review reports within 24 hours and may remove content, restrict features, suspend accounts, or terminate accounts that violate these terms.",
    ],
  },
  {
    title: "Game results",
    body: [
      "Read the World is for entertainment and social play. Scores, predictions, rankings, reveals, and percentages may change, be delayed, or be unavailable while we operate and improve the service.",
      "We may change game rules, question selection, scoring, availability, and features over time.",
    ],
  },
  {
    title: "Our service",
    body: [
      "We work to keep Read the World available and useful, but the service is provided as is and as available. We do not guarantee that it will always be uninterrupted, accurate, secure, or error-free.",
      "We may update, modify, limit, suspend, or discontinue any part of the service at any time.",
    ],
  },
  {
    title: "Intellectual property",
    body: [
      "Read the World, including its design, branding, software, questions, content, and other materials, is owned by us or our licensors and is protected by applicable laws.",
      "You may not copy, modify, reverse engineer, scrape, resell, or exploit the service except as allowed by these terms or with our written permission.",
    ],
  },
  {
    title: "Limits of liability",
    body: [
      "To the fullest extent allowed by law, we will not be liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for lost profits, data, goodwill, or business opportunities.",
      "To the fullest extent allowed by law, our total liability for any claim relating to the service will not exceed the greater of the amount you paid us to use the service in the 12 months before the claim or USD $100.",
    ],
  },
  {
    title: "Changes and contact",
    body: [
      "We may update these terms as the service changes. The effective date above shows when these terms were last updated. Continuing to use the service after changes means you accept the updated terms.",
      "Questions can be sent to mike@readtheworld.today.",
    ],
  },
];

export default function TermsPage() {
  return (
    <LegalPage
      eyebrow="Terms"
      title="Terms of Use"
      intro="These terms govern your use of Read the World."
      updated="July 11, 2026"
      sections={sections}
    />
  );
}
