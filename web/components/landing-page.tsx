import {
  ArrowRight,
  Check,
  ChevronDown,
  ChevronRight,
  Cloud,
  Coins,
  CircleDollarSign,
  Code2,
  Eye,
  FileText,
  HandCoins,
  Landmark,
  LockKeyhole,
  Orbit,
  Scale,
  ShieldCheck,
  Store,
  TimerReset,
  TrendingUp,
  UserRound,
  Wallet,
  Zap,
} from "lucide-react";
import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { LivePulse, ProtectionMark } from "@/components/live-pulse";

const navLinks = [
  { label: "Product", href: "#features", caret: true },
  { label: "For Merchants", href: "/signin" },
  { label: "Vault", href: "/vault" },
  { label: "Developers", href: "https://github.com/frankolien/recourse", external: true },
  { label: "Docs", href: "https://github.com/frankolien/recourse", external: true },
  { label: "About", href: "#how-it-works" },
];

const protections = [
  { name: "CloudCompute", ends: "Ends in 13 days", amount: "$24.00", icon: <Cloud size={15} /> },
  { name: "FileStore", ends: "Ends in 25 days", amount: "$120.00", icon: <FileText size={15} /> },
  { name: "DesignVault", ends: "Ends in 38 days", amount: "$320.00", icon: <Zap size={15} /> },
];

const stack = [
  { label: "Arc Testnet", icon: <Orbit size={17} /> },
  { label: "USDC", icon: <CircleDollarSign size={17} /> },
  { label: "USYC adapter", icon: <Coins size={17} /> },
  { label: "Deterministic engine", icon: <Scale size={17} /> },
];

const features = [
  { icon: <ShieldCheck size={20} />, tone: "green", title: "Clear protection", copy: "Refund policies are locked in before payment and cannot be changed later.", cta: "Learn more", href: "/policies" },
  { icon: <Scale size={20} />, tone: "sage", title: "Deterministic outcomes", copy: "Disputes resolve based on rules and verified evidence, not human opinion.", cta: "See how it works", href: "/verify/5" },
  { icon: <Landmark size={20} />, tone: "amber", title: "Instant settlement", copy: "Merchants get paid immediately. We handle the protection behind the scenes.", cta: "For merchants", href: "/vault" },
  { icon: <TrendingUp size={20} />, tone: "sage", title: "Yield while protected", copy: "Escrowed funds earn yield through USYC during the dispute window.", cta: "Explore the vault", href: "/vault" },
];

const workflow = [
  {
    number: "01",
    icon: <FileText size={20} />,
    title: "Policy pinned before payment",
    copy: "The merchant publishes clear refund rules onchain. Every payment stores the exact policy hash, so the terms cannot change later.",
  },
  {
    number: "02",
    icon: <LockKeyhole size={20} />,
    title: "USDC stays productive",
    copy: "Protected funds move into a yield adapter during the dispute window instead of sitting idle in a basic escrow contract.",
  },
  {
    number: "03",
    icon: <Scale size={20} />,
    title: "Evidence determines the outcome",
    copy: "The policy engine evaluates claim type, evidence, timing, and objective attestations. The first matching rule sets the refund.",
  },
  {
    number: "04",
    icon: <TimerReset size={20} />,
    title: "Settlement stays fast",
    copy: "Merchants can receive a T+0 advance from the vault while buyers retain the full protection window attached to their payment.",
  },
];

const audiences = [
  {
    icon: <UserRound size={21} />,
    eyebrow: "For buyers",
    title: "Know your protection before paying",
    copy: "Read the refund policy in plain language, submit evidence when something goes wrong, and verify the result independently.",
    points: ["Policy locked at checkout", "Refund sent to the original buyer", "Public verdict verification"],
    href: "/verify/5",
    cta: "View a protected payment",
  },
  {
    icon: <Store size={21} />,
    eyebrow: "For merchants",
    title: "Offer recourse without freezing cash flow",
    copy: "Accept protected USDC payments, publish reusable policies, and use the settlement vault to receive funds immediately.",
    points: ["Reusable policy templates", "T+0 merchant advances", "Evidence-based disputes"],
    href: "/signin",
    cta: "Open merchant dashboard",
  },
  {
    icon: <HandCoins size={21} />,
    eyebrow: "For liquidity providers",
    title: "Underwrite bounded payment risk",
    copy: "Vault liquidity advances merchants against escrow claims and earns fees plus float yield while refund exposure stays policy-bounded.",
    points: ["Transparent outstanding exposure", "Fee and yield decomposition", "Losses reflected in share value"],
    href: "/vault",
    cta: "Explore the vault",
  },
];

const faqs = [
  {
    question: "Who decides whether a buyer receives a refund?",
    answer: "The onchain policy engine computes the outcome from the policy and submitted inputs. An attestor may confirm objective facts such as delivery status, but it cannot choose the refund percentage.",
  },
  {
    question: "Can a merchant change the policy after payment?",
    answer: "No. Policies are immutable. A merchant can publish a new version for future payments, but an existing payment remains pinned to the original policy hash.",
  },
  {
    question: "Where do protected funds sit?",
    answer: "The escrow deposits USDC into a yield adapter during the protection window. The current Arc testnet deployment uses the project’s mock USYC-compatible adapter until production access is available.",
  },
  {
    question: "How can anyone verify a verdict?",
    answer: "The public verifier reads the payment and policy from Arc, computes the verdict in the browser, calls the Solidity preview function, and confirms that both verdict hashes match exactly.",
  },
  {
    question: "Is Recourse ready for mainnet funds?",
    answer: "No. This is a testnet prototype for the hackathon. The contracts, attestation model, yield integration, and operational controls require production audits and hardening before mainnet use.",
  },
];

export function LandingPage() {
  return (
    <div className="landing">
      <header className="landing-nav">
        <Link href="/" className="landing-brand">
          <BrandMark />
          <span>Recourse</span>
        </Link>
        <nav className="landing-links" aria-label="Primary">
          {navLinks.map((link) =>
            link.external ? (
              <a key={link.label} href={link.href} target="_blank" rel="noreferrer">{link.label}</a>
            ) : (
              <Link key={link.label} href={link.href}>{link.label}{link.caret && <ChevronDown size={14} />}</Link>
            ),
          )}
        </nav>
        <div className="landing-nav-actions">
          <span className="landing-chip"><LivePulse /> Arc Testnet</span>
          <Link className="landing-launch" href="/signin">Launch App</Link>
        </div>
      </header>

      <section className="landing-hero">
        <div className="landing-hero-copy">
          <span className="landing-eyebrow"><LivePulse /> Live on Arc Testnet</span>
          <h1>Buyer protection for <em>USDC payments.</em></h1>
          <p>Escrow USDC under immutable refund rules. Buyers get verifiable recourse, merchants get paid immediately, and disputes resolve from evidence instead of opinion.</p>
          <div className="landing-cta-row">
            <Link className="landing-cta" href="/verify/5">Try the live demo <ArrowRight size={16} /></Link>
            <a className="landing-cta ghost" href="https://github.com/frankolien/recourse" target="_blank" rel="noreferrer">View developer docs</a>
          </div>
          <div className="landing-proof">
            <span><Orbit size={14} /> Live contract</span>
            <span><Wallet size={14} /> 8 seeded payments</span>
            <span><ShieldCheck size={14} /> Hash-verified verdicts</span>
          </div>
        </div>

        <div className="landing-mock" aria-hidden="true">
          <article className="mock-card mock-dashboard">
            <span className="mock-title">Dashboard</span>
            <div className="mock-stat">
              <small>Total protected</small>
              <strong>$464.00</strong>
              <span>Across 3 active protections</span>
            </div>
            <span className="mock-subtitle">Active protections</span>
            <div className="mock-list">
              {protections.map((item) => (
                <div className="mock-row" key={item.name}>
                  <span className="mock-icon">{item.icon}</span>
                  <div><strong>{item.name}</strong><small>{item.ends}</small></div>
                  <b>{item.amount}</b>
                </div>
              ))}
            </div>
            <span className="mock-link">View all protections <ChevronRight size={13} /></span>
          </article>

          <article className="mock-card mock-receipt">
            <ProtectionMark className="mock-receipt-badge" />
            <span className="mock-eyebrow">Protected payment</span>
            <div className="mock-amount">24.00 <span>USDC</span></div>
            <div className="mock-paidto">
              <div><small>Paid to</small><strong>CloudCompute</strong></div>
              <span className="mock-pill green">Protected</span>
            </div>
            <dl className="mock-details">
              <div><dt>Paid</dt><dd>20 Jul 2026, 11:42 AM</dd></div>
              <div><dt>Protection ends</dt><dd>3 Aug 2026, 4:30 PM</dd></div>
              <div><dt>Policy</dt><dd>CloudCompute API Policy v1.2</dd></div>
              <div><dt>Merchant settlement</dt><dd><span className="mock-tag">Paid instantly <Check size={12} /></span></dd></div>
              <div><dt>Escrow status</dt><dd><span className="mock-tag">Earning yield <Check size={12} /></span></dd></div>
            </dl>
            <span className="mock-link center">View payment details <ChevronRight size={13} /></span>
          </article>

          <article className="mock-card mock-dispute">
            <span className="mock-title">Dispute status</span>
            <div className="mock-dispute-head">
              <div><small>Order</small><strong>#RC-284</strong></div>
              <span className="mock-pill amber">Under review</span>
            </div>
            <div className="mock-kv"><span>Evidence submitted</span><b>20 Jul, 9:18 AM</b></div>
            <div className="mock-kv"><span>Verdict</span><b>Pending</b></div>
            <div className="mock-timeline">
              <div className="mock-step done"><span /><div><strong>Submitted</strong></div></div>
              <div className="mock-step active"><span /><div><strong>Under review</strong></div></div>
              <div className="mock-step"><span /><div><strong>Decision</strong><small>Pending</small></div></div>
              <div className="mock-step"><span /><div><strong>Resolved</strong><small>Pending</small></div></div>
            </div>
            <span className="mock-link">View dispute <ChevronRight size={13} /></span>
          </article>

          <article className="mock-card mock-earnings">
            <small>Escrow earnings</small>
            <strong>+$1.24 USDC</strong>
            <span>This month</span>
            <svg viewBox="0 0 120 40" className="mock-spark" aria-hidden="true">
              <path d="M2 32 C14 30 20 24 30 26 S46 20 56 22 S72 10 84 12 S104 3 118 4" fill="none" stroke="#0d7656" strokeWidth="2.4" strokeLinecap="round" />
            </svg>
          </article>
        </div>
      </section>

      <section className="landing-stack">
        <div className="landing-stack-inner">
          <span>Live prototype stack</span>
          <div className="landing-stack-row">
            {stack.map((item) => (
              <div className="landing-stack-item" key={item.label}>{item.icon}<span>{item.label}</span></div>
            ))}
          </div>
        </div>
      </section>

      <section className="landing-features" id="features">
        <div className="landing-section-kicker">Why Recourse</div>
        <h2>A new standard for trustworthy payments</h2>
        <div className="landing-feature-grid">
          {features.map((feature) => (
            <article className="landing-feature" key={feature.title}>
              <span className={`landing-feature-icon ${feature.tone}`}>{feature.icon}</span>
              <h3>{feature.title}</h3>
              <p>{feature.copy}</p>
              <Link href={feature.href}>{feature.cta} <ArrowRight size={14} /></Link>
            </article>
          ))}
        </div>
      </section>

      <section className="landing-workflow" id="how-it-works">
        <div className="landing-section-intro">
          <div>
            <span className="landing-section-kicker">How it works</span>
            <h2>Protection without chargeback guesswork</h2>
          </div>
          <p>Recourse separates objective evidence from the final outcome. Humans and services can attest to facts, while immutable policy code decides what those facts mean.</p>
        </div>
        <div className="landing-workflow-grid">
          {workflow.map((step) => (
            <article key={step.number}>
              <span className="landing-step-number">{step.number}</span>
              <span className="landing-step-icon">{step.icon}</span>
              <h3>{step.title}</h3>
              <p>{step.copy}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="landing-verification">
        <div className="landing-verification-copy">
          <span className="landing-section-kicker">Public by design</span>
          <h2>Don’t trust the verdict. Recompute it.</h2>
          <p>The public verifier reads live Arc state and runs the same deterministic policy rules in two independent environments.</p>
          <ul>
            <li><ShieldCheck size={15} /> Solidity computes the canonical onchain result</li>
            <li><Code2 size={15} /> TypeScript recomputes the result in your browser</li>
            <li><Eye size={15} /> Matching hashes prove the outcome is reproducible</li>
          </ul>
          <Link href="/verify/5">Open the live verifier <ArrowRight size={15} /></Link>
        </div>
        <div className="landing-proof-demo">
          <div className="proof-demo-top">
            <span><LivePulse /> Payment #5</span>
            <b>Refunded 100%</b>
          </div>
          <div className="proof-demo-engine">
            <span>Solidity eth_call</span>
            <code>0x683e3c325e6e...bc650f</code>
            <b>Onchain</b>
          </div>
          <div className="proof-demo-match"><span /><ShieldCheck size={23} /><span /></div>
          <div className="proof-demo-engine">
            <span>Browser recompute</span>
            <code>0x683e3c325e6e...bc650f</code>
            <b>TypeScript</b>
          </div>
          <div className="proof-demo-success"><Check size={17} /><span><strong>Hashes match exactly</strong><small>No backend chose this verdict.</small></span></div>
        </div>
      </section>

      <section className="landing-audiences" id="merchants">
        <div className="landing-section-intro centered">
          <div>
            <span className="landing-section-kicker">One payment, aligned incentives</span>
            <h2>Built for every side of protected commerce</h2>
          </div>
          <p>Buyers keep recourse, merchants keep velocity, and liquidity providers can see the exact risk they are underwriting.</p>
        </div>
        <div className="landing-audience-grid">
          {audiences.map((audience) => (
            <article key={audience.eyebrow}>
              <span className="landing-audience-icon">{audience.icon}</span>
              <small>{audience.eyebrow}</small>
              <h3>{audience.title}</h3>
              <p>{audience.copy}</p>
              <ul>{audience.points.map((point) => <li key={point}><Check size={13} /> {point}</li>)}</ul>
              <Link href={audience.href}>{audience.cta} <ChevronRight size={14} /></Link>
            </article>
          ))}
        </div>
      </section>

      <section className="landing-vault-story">
        <div>
          <span className="landing-section-kicker">The DeFi engine</span>
          <h2>Protection that does not force merchants to wait</h2>
          <p>The settlement vault advances enrolled merchants against protected escrow claims. Liquidity providers earn the advance fee and float yield, then absorb any policy-defined refund loss.</p>
          <Link href="/vault">See vault mechanics <ArrowRight size={15} /></Link>
        </div>
        <div className="vault-equation">
          <span>LP net return</span>
          <div><b>Advance fees</b><strong>+</strong><b>Float yield</b><strong>−</strong><b>Refund losses</b></div>
          <small>Every component is visible in the vault dashboard.</small>
        </div>
      </section>

      <section className="landing-faq" id="faq">
        <div className="landing-faq-heading">
          <span className="landing-section-kicker">Questions, answered</span>
          <h2>What protected USDC payments actually mean</h2>
          <p>Recourse is intentionally narrow: immutable policies, deterministic outcomes, productive escrow, and transparent settlement risk.</p>
        </div>
        <div className="landing-faq-list">
          {faqs.map((faq, index) => (
            <details key={faq.question} open={index === 0}>
              <summary>{faq.question}<span>+</span></summary>
              <p>{faq.answer}</p>
            </details>
          ))}
        </div>
      </section>

      <section className="landing-final-cta">
        <div>
          <span className="landing-section-kicker">Live on Arc Testnet</span>
          <h2>See protected payments resolve in public.</h2>
          <p>Explore the dashboard, inspect a seeded payment, and change the evidence inputs yourself.</p>
        </div>
        <div>
          <Link className="landing-cta light" href="/signin">Launch the app <ArrowRight size={16} /></Link>
          <Link className="landing-cta outline-light" href="/verify/5">Verify payment #5</Link>
        </div>
      </section>

      <footer className="landing-footer">
        <div className="landing-footer-brand"><BrandMark /><span>Recourse</span></div>
        <p>Buyer protection for USDC payments on Arc. Testnet prototype.</p>
        <div className="landing-footer-links">
          <Link href="/signin">Launch App</Link>
          <Link href="/verify/5">Verifier</Link>
          <a href="https://github.com/frankolien/recourse" target="_blank" rel="noreferrer">GitHub</a>
        </div>
      </footer>
    </div>
  );
}
