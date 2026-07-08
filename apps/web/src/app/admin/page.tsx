import type { Metadata } from "next";
import { AdminPanel, type AdminView } from "@/components/AdminPanel";

export const metadata: Metadata = {
  title: "Admin",
  robots: {
    index: false,
    follow: false,
  },
};

const adminViews: AdminView[] = [
  "bank",
  "world",
  "rooms",
  "today",
  "schedule",
  "library",
  "analytics",
  "results",
  "notifications",
  "settings",
];

function adminViewFromParam(value: string | string[] | undefined): AdminView {
  const requested = Array.isArray(value) ? value[0] : value;
  return adminViews.includes(requested as AdminView) ? requested as AdminView : "today";
}

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ view?: string | string[] }>;
}) {
  const params = await searchParams;
  return <AdminPanel initialView={adminViewFromParam(params.view)} />;
}
