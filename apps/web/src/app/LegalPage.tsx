import Link from "next/link";

type LegalSection = {
  title: string;
  body: string[];
};

type LegalPageProps = {
  eyebrow: string;
  title: string;
  intro: string;
  updated: string;
  sections: LegalSection[];
};

export function LegalPage({ eyebrow, title, intro, updated, sections }: LegalPageProps) {
  return (
    <main className="legalPage">
      <header className="supportNav">
        <Link className="wordmark" href="/">
          read the world<span>.</span>
        </Link>
        <Link className="supportNavLink" href="/">
          Back home
        </Link>
      </header>

      <article className="legalWrap">
        <div className="legalIntro">
          <div className="eyebrow clay">{eyebrow}</div>
          <h1 className="serif">{title}</h1>
          <p>{intro}</p>
          <span>Effective {updated}</span>
        </div>

        <div className="legalSections">
          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </article>

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
