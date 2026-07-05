import type { Metadata } from "next";
import Link from "next/link";
import { SupportContactForm } from "./SupportContactForm";

export const metadata: Metadata = {
  title: "Support",
  description: "Contact Read the World support.",
  alternates: {
    canonical: "/support",
  },
};

export default function SupportPage() {
  return (
    <main className="supportPage">
      <header className="supportNav">
        <Link className="wordmark" href="/">
          read the world<span>.</span>
        </Link>
        <Link className="supportNavLink" href="/">
          Back home
        </Link>
      </header>

      <section className="supportWrap">
        <div className="supportIntro">
          <div className="eyebrow clay">Support</div>
          <h1 className="serif">Need a hand?</h1>
          <p>Send a note and we&apos;ll reply by email.</p>
        </div>
        <SupportContactForm />
      </section>

      <footer className="supportFooter">
        <Link className="wordmark" href="/">
          read the world<span>.</span>
        </Link>
        <div className="supportFooterLinks">
          <Link href="/support">Support</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
        </div>
      </footer>
    </main>
  );
}
