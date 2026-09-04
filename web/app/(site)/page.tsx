import type { Metadata } from "next";
import Image from "next/image";
import { ArrowLeftRight, ArrowUpRight, FileText, KeyRound, Sprout } from "lucide-react";
import { DownloadButton } from "@/components/site/download-button";
import { GITHUB_URL } from "@/components/site/footer";
import { ChequeSlip, ConvertPair, EarnCurve, FeeTag, HandleChips } from "@/components/site/illustrations";
import { PhoneShot } from "@/components/site/phone";
import { SecurityCarousel } from "@/components/site/security-carousel";

export const metadata: Metadata = {
  title: { absolute: "Recourse" },
  description: "Dollars on your phone, sent by name.",
};

export default function HomePage() {
  return (
    <>
      <section className="site-wrap site-hero" aria-labelledby="hero-title">
        <h1 id="hero-title" className="site-h1">
          Money that moves like a message.
        </h1>
        <p className="site-sub">Dollars on your phone, sent by name.</p>
        <div className="site-hero-cta">
          <DownloadButton />
          <p className="site-hero-note">Now in beta on TestFlight.</p>
        </div>
        <div className="site-hero-panel">
          <PhoneShot
            src="/app/home.png"
            alt="The Recourse home screen: a balance of forty dollars, Add money and Send, and the Cheques, Request, Convert and Earn cards"
            priority
          />
        </div>
      </section>

      <section className="site-wrap site-section" aria-labelledby="not-a-wallet">
        <div className="site-section-head">
          <h2 id="not-a-wallet" className="site-h2">
            Recourse isn&apos;t another crypto wallet.
          </h2>
          <p className="site-sub">
            It is a money app. Your dollars live in a smart account on Arc, and every screen is about paying, collecting,
            or growing them. Nothing to write down, no second coin for fees, no addresses to copy.
          </p>
        </div>
        <div className="site-bento">
          <article className="site-card site-card-dark">
            <div className="site-card-art">
              <EarnCurve />
            </div>
            <h3 className="site-card-title">Earn on idle dollars</h3>
            <p className="site-card-text">Put USDC into Earn and watch it grow while it sits.</p>
          </article>
          <div className="site-bento-right">
            <article className="site-card site-card-light">
              <div className="site-card-art">
                <HandleChips />
              </div>
              <h3 className="site-card-title">Send dollars by name</h3>
              <p className="site-card-text">Pay anyone by their @handle. No addresses to copy.</p>
            </article>
            <article className="site-card site-card-light">
              <div className="site-card-art">
                <ChequeSlip />
              </div>
              <h3 className="site-card-title">Write cheques, cash them later</h3>
              <p className="site-card-text">
                A cheque waits in the other person&apos;s app until they cash it, and you can void it before they do.
              </p>
            </article>
            <article className="site-card site-card-light">
              <div className="site-card-art">
                <ConvertPair />
              </div>
              <h3 className="site-card-title">Convert between dollars and euros</h3>
              <p className="site-card-text">USDC to EURC at a rate the app checks before you sign.</p>
            </article>
            <article className="site-card site-card-light">
              <div className="site-card-art">
                <FeeTag />
              </div>
              <h3 className="site-card-title">Fees in the money you already hold</h3>
              <p className="site-card-text">
                Gas on Arc is paid in USDC. You never buy a second coin to move your own money.
              </p>
            </article>
          </div>
        </div>
      </section>

      <section className="site-wrap site-section" aria-labelledby="everyday">
        <div className="site-split">
          <div className="site-split-copy">
            <h2 id="everyday" className="site-h2">
              Use dollars as everyday money
            </h2>
            <ul className="site-feature-list">
              <li>
                <h3>Send by name</h3>
                <p>Type an @handle, an amount, and a note. No address to check, and the fee comes out of the same dollars.</p>
              </li>
              <li>
                <h3>Request money</h3>
                <p>Bill someone by name and collect when they sign. The request waits in their app until they pay it.</p>
              </li>
            </ul>
          </div>
          <div className="site-panel">
            <PhoneShot src="/app/send.png" alt="Sending 12 USDC to @olien, confirmed with Face ID" />
          </div>
        </div>
      </section>

      <section className="site-wrap site-section" aria-label="Earn, cheques and convert">
        <ul className="site-trio">
          <li className="site-trio-item">
            <span className="site-icon-tile">
              <Sprout size={22} strokeWidth={1.9} aria-hidden="true" />
            </span>
            <h3>Earn</h3>
            <p>Yield on idle USDC</p>
          </li>
          <li className="site-trio-item">
            <span className="site-icon-tile">
              <FileText size={22} strokeWidth={1.9} aria-hidden="true" />
            </span>
            <h3>Cheques</h3>
            <p>Write, cash or void</p>
          </li>
          <li className="site-trio-item">
            <span className="site-icon-tile">
              <ArrowLeftRight size={22} strokeWidth={1.9} aria-hidden="true" />
            </span>
            <h3>Convert</h3>
            <p>USDC to EURC</p>
          </li>
        </ul>
      </section>

      <section className="site-wrap site-section" aria-labelledby="security">
        <SecurityCarousel />
      </section>

      <section className="site-wrap site-section" aria-label="Arc and your keys">
        <div className="site-duo">
          <article className="site-card site-card-dark">
            <span className="site-icon-tile">
              <Image src="/brand/arc-mark.svg" alt="" width={22} height={23} />
            </span>
            <div>
              <h3 className="site-h3">Arc&apos;s security standard</h3>
              <p className="site-card-text">
                Recourse runs on smart accounts on Arc, Circle&apos;s blockchain, where the money is USDC and the rules
                are enforced by the chain.
              </p>
            </div>
          </article>
          <article className="site-card site-card-light">
            <span className="site-icon-tile">
              <KeyRound size={22} strokeWidth={1.9} aria-hidden="true" />
            </span>
            <div>
              <h3 className="site-h3">Your money. Your keys.</h3>
              <p className="site-card-text">
                Ownership is enforced by Arc&apos;s validators, not by us. We never hold a key that can move your money on
                its own.
              </p>
            </div>
          </article>
        </div>
        <p className="site-code">
          <span>Read the code and the docs.</span>
          <a href={GITHUB_URL} target="_blank" rel="noreferrer" className="site-circle-link" aria-label="Recourse on GitHub">
            <ArrowUpRight size={18} strokeWidth={2} aria-hidden="true" />
          </a>
        </p>
      </section>

      <section className="site-wrap site-cta" aria-labelledby="get-started">
        <Image src="/brand/recourse-mark.png" alt="The Recourse app icon" width={80} height={80} className="site-cta-icon" />
        <h2 id="get-started" className="site-h2">
          Get started with Recourse today.
        </h2>
        <p className="site-sub">The money app for dollars on your phone.</p>
        <DownloadButton />
      </section>
    </>
  );
}
