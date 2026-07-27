import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";

export const metadata: Metadata = {
  title: "Privacy policy",
  description: "What Recourse collects, what never leaves your device, and what lives permanently on the public Arc chain.",
};

export default function PrivacyPage() {
  return (
    <div className="legal-page">
      <header className="legal-brand">
        <Link href="/" className="legal-brand-link">
          <BrandMark />
          <span>Recourse</span>
        </Link>
      </header>

      <main className="legal-body">
        <h1>Privacy policy</h1>
        <p className="legal-updated">Last updated July 25, 2026</p>

        <p>
          Recourse provides buyer protection for USDC payments on the Arc testnet.
          This policy covers the Recourse iOS app and the web app at
          recourse-arc.vercel.app. It is written to be read, not skimmed past: the
          product&apos;s whole premise is that you should not have to trust us, and
          that starts with being plain about data.
        </p>

        <h2>What we collect</h2>
        <p>
          <strong>Account details.</strong> When you sign in with Google, Apple, a
          passkey, or email, we store your email address and display name to
          operate your session and identify your workspace.
        </p>
        <p>
          <strong>Content you upload.</strong> Merchants upload product photos and
          order details. Buyers who report a problem upload evidence photos. This
          content is stored by our backend, addressed by its cryptographic hash,
          and mirrored to a content delivery network so it loads quickly. Evidence
          is used only to resolve the dispute it was filed for.
        </p>
        <p>
          <strong>Payment data, which is public by design.</strong> Payments,
          refund policies, disputes, attestations, and verdicts are recorded on
          the public Arc blockchain. Anyone can read them, and they cannot be
          edited or deleted by anyone, including us. Wallet addresses are
          pseudonymous but permanent.
        </p>

        <h2>What never leaves your device</h2>
        <p>
          <strong>Wallet keys.</strong> The iOS app generates and stores your
          signing keys in the device&apos;s Secure Enclave. We never see, transmit,
          or hold them. The web app&apos;s provisioned testnet wallet is stored in
          your browser&apos;s local storage.
        </p>
        <p>
          <strong>Face ID.</strong> Biometric checks run entirely through
          Apple&apos;s system frameworks on your device. No biometric data reaches
          us, ever.
        </p>
        <p>
          <strong>Camera.</strong> The camera is used to scan checkout QR codes.
          Frames are processed on the device and are not recorded or uploaded.
        </p>

        <h2>What we do not do</h2>
        <p>
          No advertising, no analytics trackers, no selling or sharing of data
          with third parties for marketing, no profiling. The backend logs
          ordinary operational records (such as request errors) to keep the
          service running.
        </p>

        <h2>Retention and deletion</h2>
        <p>
          Account details and uploaded content are kept while your account is
          active. Email us to delete your account and off-chain content. Data
          recorded on the Arc blockchain is immutable and cannot be deleted by
          design; that permanence is what makes verdicts verifiable.
        </p>

        <h2>Testnet notice</h2>
        <p>
          Recourse currently runs on the Arc testnet. Balances are test tokens
          with no monetary value, and no real funds are handled.
        </p>

        <h2>Contact</h2>
        <p>
          Questions or deletion requests: <a href="mailto:gkenny896@gmail.com">gkenny896@gmail.com</a>.
        </p>
      </main>

      <footer className="legal-footer">
        <Link href="/">Recourse home</Link>
        <Link href="/terms">Terms of service</Link>
        <Link href="/verify/13">Public verifier</Link>
      </footer>
    </div>
  );
}
