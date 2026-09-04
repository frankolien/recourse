import Link from "next/link";

export const GITHUB_URL = "https://github.com/frankolien/recourse";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="site-wrap site-footer-inner">
        <p className="site-footer-copy">Recourse. Dollars on your phone, on Arc testnet.</p>
        <nav className="site-footer-links" aria-label="Footer">
          <Link href="/terms">Terms</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/support">Support</Link>
          <a href={GITHUB_URL} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </nav>
      </div>
    </footer>
  );
}
