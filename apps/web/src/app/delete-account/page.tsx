import type { Metadata } from "next";
import { LegalPage } from "../LegalPage";

export const metadata: Metadata = {
  title: "Delete Your Account",
  description: "How to delete your Read the World account and associated data.",
  alternates: {
    canonical: "/delete-account",
  },
};

const sections = [
  {
    title: "Delete your account in the app",
    body: [
      "Open Read the World, go to Profile, choose Delete account, and confirm the deletion. This permanently deletes your Read the World account and signs you out.",
    ],
  },
  {
    title: "Request deletion by email",
    body: [
      "If you cannot access the app, email mike@readtheworld.today from the address associated with your account and ask us to delete your Read the World account. We may ask you to verify that you own the account before completing the request.",
    ],
  },
  {
    title: "Delete specific data without deleting your account",
    body: [
      "You can also email mike@readtheworld.today from the address associated with your account and identify the specific personal data you want deleted. We may ask you to verify that you own the account and may retain information needed to keep the service secure, meet legal obligations, or preserve other members' room results.",
    ],
  },
  {
    title: "What is deleted",
    body: [
      "Account information and data associated with your account are deleted, including your profile, room memberships, answers, predictions, scores, preferences, and notification tokens.",
      "Some information may remain temporarily in encrypted backups, security logs, aggregated statistics, or records that we are legally required to retain. These records are not used to restore your account and are removed according to their normal retention schedules.",
    ],
  },
];

export default function DeleteAccountPage() {
  return (
    <LegalPage
      eyebrow="Account deletion"
      title="Delete your Read the World account"
      intro="You can permanently delete your account in the app or request deletion by email."
      updated="July 17, 2026"
      sections={sections}
    />
  );
}
