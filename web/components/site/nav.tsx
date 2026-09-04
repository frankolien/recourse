import Image from "next/image";
import Link from "next/link";
import { DownloadButton } from "./download-button";

export function SiteNav() {
  return (
    <header className="site-nav">
      <div className="site-wrap site-nav-inner">
        <Link href="/" className="site-logo" aria-label="Recourse home">
          <Image src="/brand/recourse-mark.png" alt="" width={32} height={32} className="site-logo-mark" priority />
          <span className="site-logo-word">Recourse</span>
        </Link>
        <nav className="site-nav-links" aria-label="Primary">
          <Link href="/support">Support</Link>
          <Link href="/olien">Olien</Link>
          <DownloadButton size="small" />
        </nav>
      </div>
    </header>
  );
}
