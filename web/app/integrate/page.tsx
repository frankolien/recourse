import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";

export const metadata: Metadata = {
  title: "Integrate",
  description:
    "Put a Pay with Recourse button on any website: one link gives your checkout escrow, locked refund policies, and verdicts anyone can recompute.",
};

const snippet = `<a href="YOUR_CHECKOUT_LINK">
  <img src="https://recourse-arc.vercel.app/brand/pay-with-recourse.svg"
       alt="Pay with Recourse" height="48" />
</a>`;

export default function IntegratePage() {
  return (
    <div className="legal-page">
      <header className="legal-brand">
        <Link href="/" className="legal-brand-link">
          <BrandMark />
          <span>Recourse</span>
        </Link>
      </header>

      <main className="legal-body">
        <h1>Put Recourse on your checkout</h1>
        <p className="legal-updated">One link. No SDK, no JavaScript, no backend.</p>

        <p>
          Every Recourse checkout is a URL. Put that URL behind a button on your
          site, your link-in-bio, or your product page, and buyers who click it
          pay you in USDC with escrow, a refund policy locked at payment, and
          dispute verdicts anyone can recompute. You do not integrate an API;
          you paste a link.
        </p>

        <h2>The button</h2>
        <div className="integrate-buttons">
          {/* Plain img tags on purpose: this is exactly what merchants embed. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/brand/pay-with-recourse.svg" alt="Pay with Recourse" height={48} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/brand/pay-with-recourse-light.svg" alt="Pay with Recourse, light" height={48} />
        </div>
        <p>
          Two variants, both served from this domain and free to hotlink or
          copy: <a href="/brand/pay-with-recourse.svg">green</a> for light
          pages, <a href="/brand/pay-with-recourse-light.svg">light</a> for
          dark or colorful pages.
        </p>

        <h2>The embed</h2>
        <pre className="integrate-snippet">
          <code>{snippet}</code>
        </pre>
        <p>
          Get <code>YOUR_CHECKOUT_LINK</code> from the Recourse iOS app: publish
          a checkout in the merchant workspace and tap{" "}
          <strong>Copy embed code</strong>, which copies this snippet with the
          link already filled in. Reusable checkouts keep one stable link for a
          product you always sell; one-off checkouts get a fresh link per deal.
        </p>

        <h2>What happens on click</h2>
        <p>
          The link is a universal link. On an iPhone with Recourse installed it
          opens straight into the in-app checkout, with the price and the exact
          refund policy shown before any money moves. Without the app it lands
          on the hosted checkout page here, which can hand off to the App Store
          or complete the flow on the web. Either way the payment escrows on
          Arc under the hashed policy, so neither side can rewrite the terms
          afterward.
        </p>

        <h2>Verify without trusting us</h2>
        <p>
          Every payment made through the button gets a public record. The{" "}
          <Link href="/verify/13">verifier</Link> recomputes any verdict from
          on-chain inputs in the browser, so your buyers can check outcomes
          without an account, an app, or faith in Recourse.
        </p>

        <h2>Testnet notice</h2>
        <p>
          Recourse currently runs on Arc testnet: payments use test USDC with
          no monetary value, so you can integrate and rehearse the full flow
          before real funds exist. Questions or an integration we should
          support next: <a href="mailto:gkenny896@gmail.com">gkenny896@gmail.com</a>.
        </p>
      </main>

      <footer className="legal-footer">
        <Link href="/">Recourse home</Link>
        <a href="https://github.com/frankolien/recourse">GitHub</a>
      </footer>
    </div>
  );
}
