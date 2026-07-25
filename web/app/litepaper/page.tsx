import fs from "node:fs";
import path from "node:path";
import type { Metadata } from "next";
import Link from "next/link";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { BrandMark } from "@/components/brand-mark";

export const metadata: Metadata = {
  title: "Litepaper",
  description: "Recourse litepaper: deterministic buyer protection for USDC payments on Arc. Disputes are computed, not decided.",
};

// The canonical litepaper lives in docs/ at the repo root; this page renders
// those exact bytes so the site and the repository can never drift apart.
function litepaperSource(): string {
  const candidates = [
    path.join(process.cwd(), "..", "docs", "litepaper.md"),
    path.join(process.cwd(), "docs", "litepaper.md"),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return fs.readFileSync(candidate, "utf8");
  }
  throw new Error("litepaper.md not found");
}

export default function LitepaperPage() {
  const source = litepaperSource();
  return (
    <div className="legal-page">
      <header className="legal-brand">
        <Link href="/" className="legal-brand-link">
          <BrandMark />
          <span>Recourse</span>
        </Link>
      </header>

      <main className="legal-body paper-body">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{source}</ReactMarkdown>
      </main>

      <footer className="legal-footer">
        <Link href="/">Recourse home</Link>
        <Link href="/verify/13">Public verifier</Link>
        <Link href="/vault">Vault</Link>
      </footer>
    </div>
  );
}
