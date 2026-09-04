import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of service",
  description:
    "The terms for using Recourse on Arc testnet: test funds only, a 2-of-3 account the chain enforces, and what we do and do not promise.",
};

export default function TermsPage() {
  return (
    <article className="site-wrap site-legal">
      <h1 className="site-h1">Terms of service</h1>
      <p className="site-legal-updated">Last updated September 4, 2026</p>

      <p>
        These terms cover the Recourse iOS app, the website at recourse-arc.vercel.app, and Olien, the web console for
        team treasuries. Using any of them means you accept them. They are short because the product currently runs on
        a test network; they will grow up when the money does.
      </p>

      <h2>Testnet only, no real money</h2>
      <p>
        Recourse runs on the Arc testnet. Every balance is test USDC or test EURC with no monetary value. Nothing you
        send, request, cash, convert, or put into Earn through the service is real funds, and nothing here is an offer
        of financial services, investment advice, or banking.
      </p>

      <h2>How your account works</h2>
      <p>
        Your account is a 2-of-3 smart account on Arc. One key lives in your phone&apos;s Secure Enclave, one in your
        iCloud, and one is a sealed recovery key held by our backend. Two of them must sign together for any payment,
        and the chain enforces that rule, not us. The key we hold cannot move your money on its own, and it cannot bring
        an account back on a new phone without your iCloud key. Olien treasuries work the same way for teams: who can
        propose and who must sign is set by the members and enforced on chain.
      </p>

      <h2>Your responsibilities</h2>
      <p>
        Keep your phone and your Apple account secure; the keys on them sign for you, and payments they sign are yours.
        Check the @handle before you send, because once a payment is on the chain we cannot reverse it. A cheque can be
        voided until the moment it is cashed and a request can be ignored, but a sent payment is final. Do not use the
        service for anything unlawful.
      </p>

      <h2>What we promise, and what we do not</h2>
      <p>
        The service is provided as is, without warranties of uptime, fitness, or availability. Chain data is permanent,
        but the app, the backend, Olien, and the test deployment may change, break, or be reset at any time while
        Recourse is in development. To the maximum extent the law allows, our liability to you is zero, which on a
        network where balances are worth zero is also exactly proportionate.
      </p>

      <h2>Accounts and deletion</h2>
      <p>
        You can ask us to delete your handle and anything we hold off-chain at any time; see the{" "}
        <Link href="/privacy">privacy policy</Link> for what deletion can and cannot cover, since on-chain records are
        immutable by design.
      </p>

      <h2>Changes</h2>
      <p>
        We may update these terms as the product evolves. The date above changes when the terms do, and continued use
        after a change means acceptance.
      </p>

      <h2>Contact</h2>
      <p>
        Questions about these terms: <a href="mailto:gkenny896@gmail.com">gkenny896@gmail.com</a>.
      </p>
    </article>
  );
}
