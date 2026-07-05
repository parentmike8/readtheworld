import type { Metadata } from "next";
import { LegalPage } from "../LegalPage";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "Read the World privacy policy.",
  alternates: {
    canonical: "/privacy",
  },
};

const sections = [
  {
    title: "Information we collect",
    body: [
      "We collect the information you provide when you create an account, including your email address, display name, profile color, authentication method, and any feedback or support messages you send.",
      "We collect game activity in the app, including rooms you create or join, questions shown to you, answers, predictions, scores, question likes and dislikes, party mode activity, invitations, and notification preferences.",
      "We also collect basic device, log, analytics, crash, and performance information so we can run, secure, debug, and improve the service.",
    ],
  },
  {
    title: "How we use information",
    body: [
      "We use information to create and secure accounts, run daily rooms and party mode, calculate scores, send verification and product emails, respond to support requests, improve question selection, and understand how the app is working.",
      "We may use aggregate or de-identified information to understand game trends, improve the product, and decide which questions work best.",
    ],
  },
  {
    title: "Sharing",
    body: [
      "We do not sell your personal information.",
      "We share information with service providers that help us operate the app, including cloud hosting, authentication, database, analytics, crash reporting, messaging, email delivery, and app distribution providers.",
      "Your answers, predictions, and scores may be shown to other people in your rooms, party games, or app experiences where the product is designed to compare or reveal group results. We may also disclose information if required by law or to protect the service, our users, or others.",
    ],
  },
  {
    title: "Retention and deletion",
    body: [
      "We keep information for as long as needed to provide the app, maintain records, resolve issues, enforce our terms, and comply with legal obligations.",
      "You can request deletion of your account or personal information by contacting us at mike@readtheworld.today. Some information may remain in backups, logs, aggregated statistics, or records we are required to keep.",
    ],
  },
  {
    title: "Notifications and email",
    body: [
      "If you enable notifications, we use push tokens to send app notifications such as room reminders. You can turn notifications off in your device settings or app settings.",
      "We may send service emails such as account verification, support replies, feedback follow-up, and account-related notices.",
    ],
  },
  {
    title: "Children",
    body: [
      "Read the World is not intended for children under 13. If you believe a child under 13 has provided personal information, contact us and we will take appropriate steps to delete it.",
    ],
  },
  {
    title: "Security and international processing",
    body: [
      "We use reasonable technical and organizational measures to protect information, but no online service can be guaranteed to be completely secure.",
      "Information may be processed in the United States, Canada, or other countries where we or our service providers operate.",
    ],
  },
  {
    title: "Changes and contact",
    body: [
      "We may update this policy as the service changes. The effective date above shows when this policy was last updated.",
      "Questions or requests can be sent to mike@readtheworld.today.",
    ],
  },
];

export default function PrivacyPage() {
  return (
    <LegalPage
      eyebrow="Privacy"
      title="Privacy Policy"
      intro="This policy explains what Read the World collects, how we use it, and the choices you have."
      updated="July 5, 2026"
      sections={sections}
    />
  );
}
