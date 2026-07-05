import Link from "next/link";

export default function NotFound() {
  return (
    <main className="notFoundPage">
      <header className="supportNav">
        <Link className="wordmark" href="/">
          read the world<span>.</span>
        </Link>
        <Link className="supportNavLink" href="/support">
          Support
        </Link>
      </header>

      <section className="notFoundWrap">
        <div className="eyebrow clay">404</div>
        <h1 className="serif">That page is out of bounds.</h1>
        <p>Head back to today&apos;s read or contact support.</p>
        <div className="notFoundActions">
          <Link className="darkButton" href="/">
            Back home
          </Link>
          <Link className="notFoundSupportLink" href="/support">
            Contact support
          </Link>
        </div>
      </section>
    </main>
  );
}
