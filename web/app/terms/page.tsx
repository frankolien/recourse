import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";

export const metadata: Metadata = {
  title: "Terms of service",
  description:
    "The terms for using Recourse on Arc testnet: test funds only, deterministic verdicts are final, and what we do and do not promise.",
};

export default function TermsPage() {
  return (
    <div className="legal-page">
      <header className="legal-brand">
        <Link href="/" className="legal-brand-link">
          <BrandMark />
          <span>Recourse</span>
        </Link>
      </header>

      <main className="legal-body">
        <h1>Terms of service</h1>
        <p className="legal-updated">Last updated July 27, 2026</p>

        <p>
          These terms cover the Recourse iOS app and the web app at
          recourse-arc.vercel.app. Using either means you accept them. They are
          short because the product currently runs on a test network; they will
          grow up when the money does.
        </p>

        <h2>Testnet only, no real money</h2>
        <p>
          Recourse runs on the Arc testnet. Every balance is test USDC with no
          monetary value. Nothing you deposit, escrow, win, or lose through the
          service is real funds, and nothing here is an offer of financial
          services, investment advice, or banking.
        </p>

        <h2>How disputes are decided</h2>
        <p>
          Refund policies are machine-readable and locked by hash at the moment
          of payment. Disputes are decided by a deterministic policy engine
          from the locked policy, the claim, the submitted evidence, and the
          timing, and by nothing else. By paying through a protected checkout
          you agree that this computed verdict is the outcome of the dispute.
          There is no human appeal, and that is the product&apos;s core promise:
          the same inputs produce the same verdict for everyone, and anyone
          can recompute it from public chain data.
        </p>

        <h2>Your responsibilities</h2>
        <p>
          Keep your device and sign-in method secure; the wallet key lives on
          your phone and transactions it signs are yours. File disputes within
          the policy&apos;s claim window, since the window is enforced by the
          engine, not by our goodwill. Upload only evidence you have the right
          to share, and do not use the service for anything unlawful.
        </p>

        <h2>What we promise, and what we do not</h2>
        <p>
          The service is provided as is, without warranties of uptime,
          fitness, or availability. Chain data is permanent, but the apps, the
          indexer, and the test deployment may change, break, or be reset at
          any time while Recourse is in development. To the maximum extent the
          law allows, our liability to you is zero, which on a network where
          balances are worth zero is also exactly proportionate.
        </p>

        <h2>Accounts and deletion</h2>
        <p>
          You can request deletion of your account and off-chain content at
          any time; see the <Link href="/privacy">privacy policy</Link> for
          what deletion can and cannot cover, since on-chain records are
          immutable by design.
        </p>

        <h2>Changes</h2>
        <p>
          We may update these terms as the product evolves. The date above
          changes when the terms do, and continued use after a change means
          acceptance.
        </p>

        <h2>Contact</h2>
        <p>
          Questions about these terms:{" "}
          <a href="mailto:gkenny896@gmail.com">gkenny896@gmail.com</a>.
        </p>
      </main>

      <footer className="legal-footer">
        <Link href="/">Recourse home</Link>
        <Link href="/privacy">Privacy policy</Link>
      </footer>
    </div>
  );
}
