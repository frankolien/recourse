import {
  ArrowRight,
  Check,
  ChevronDown,
  ChevronRight,
  Cloud,
  Coins,
  CircleDollarSign,
  FileText,
  Landmark,
  Network,
  Orbit,
  Repeat,
  Scale,
  ShieldCheck,
  TrendingUp,
  Wallet,
  Zap,
} from "lucide-react";
import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";

const navLinks = [
  { label: "Product", href: "#features", caret: true },
  { label: "For Merchants", href: "/vault" },
  { label: "Vault", href: "/vault" },
  { label: "Developers", href: "https://github.com/frankolien/recourse", external: true },
  { label: "Docs", href: "https://github.com/frankolien/recourse", external: true },
  { label: "About", href: "#features" },
];

const protections = [
  { name: "CloudCompute", ends: "Ends in 13 days", amount: "$24.00", icon: <Cloud size={15} /> },
  { name: "FileStore", ends: "Ends in 25 days", amount: "$120.00", icon: <FileText size={15} /> },
  { name: "DesignVault", ends: "Ends in 38 days", amount: "$320.00", icon: <Zap size={15} /> },
];

const stack = [
  { label: "Arc", icon: <Orbit size={17} /> },
  { label: "USDC", icon: <CircleDollarSign size={17} /> },
  { label: "USYC", icon: <Coins size={17} /> },
  { label: "Gateway", icon: <Network size={17} /> },
  { label: "CCTP", icon: <Repeat size={17} /> },
  { label: "Circle Wallets", icon: <Wallet size={17} /> },
  { label: "Paymaster", icon: <ShieldCheck size={17} /> },
  { label: "Nanopayments", icon: <Zap size={17} /> },
];

const features = [
  { icon: <ShieldCheck size={20} />, tone: "green", title: "Clear protection", copy: "Refund policies are locked in before payment and cannot be changed later.", cta: "Learn more", href: "/policies" },
  { icon: <Scale size={20} />, tone: "sage", title: "Deterministic outcomes", copy: "Disputes resolve based on rules and verified evidence, not human opinion.", cta: "See how it works", href: "/verify/5" },
  { icon: <Landmark size={20} />, tone: "amber", title: "Instant settlement", copy: "Merchants get paid immediately. We handle the protection behind the scenes.", cta: "For merchants", href: "/vault" },
  { icon: <TrendingUp size={20} />, tone: "sage", title: "Yield while protected", copy: "Escrowed funds earn yield through USYC during the dispute window.", cta: "Explore the vault", href: "/vault" },
];

const avatars = [
  { bg: "#ece5d8", skin: "#d9a97f", hair: "#3a2a20", shirt: "#6b7f74" },
  { bg: "#e5e9ea", skin: "#a9754f", hair: "#20160f", shirt: "#48596a" },
  { bg: "#e9e7de", skin: "#e7bd93", hair: "#6a4a30", shirt: "#8a7d5f" },
];

// Flat portrait avatars for social proof: head, hair, and shoulders in diverse
// tones, drawn inline so the page stays offline and uses no stranger photos.
function Avatar({ bg, skin, hair, shirt, index }: { bg: string; skin: string; hair: string; shirt: string; index: number }) {
  const clip = `avatar-clip-${index}`;
  return (
    <svg viewBox="0 0 48 48" className="landing-avatar" aria-hidden="true">
      <defs>
        <clipPath id={clip}><circle cx="24" cy="24" r="24" /></clipPath>
      </defs>
      <g clipPath={`url(#${clip})`}>
        <rect width="48" height="48" fill={bg} />
        <rect x="20.5" y="26" width="7" height="10" fill={skin} />
        <ellipse cx="24" cy="49" rx="15" ry="12" fill={shirt} />
        <circle cx="24" cy="20.5" r="9" fill={skin} />
        <path d="M14.5 22 C14 12 34 12 33.5 22 C33 17 29.5 15.5 24 15.5 C18.5 15.5 15 17 14.5 22 Z" fill={hair} />
      </g>
    </svg>
  );
}

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
          <span className="landing-chip"><span className="landing-dot" /> Arc Testnet</span>
          <Link className="landing-launch" href="/dashboard">Launch App</Link>
        </div>
      </header>

      <section className="landing-hero">
        <div className="landing-hero-copy">
          <span className="landing-eyebrow"><ShieldCheck size={14} /> Built on Arc by Circle</span>
          <h1>Buyer protection for <em>USDC payments.</em></h1>
          <p>Recourse adds programmable protection to stablecoin payments. Clear policies. Deterministic dispute resolution. Instant settlement for merchants.</p>
          <div className="landing-cta-row">
            <Link className="landing-cta" href="/dashboard">Start building <ArrowRight size={16} /></Link>
            <Link className="landing-cta ghost" href="/verify/5">Explore the demo</Link>
          </div>
          <div className="landing-proof">
            <div className="landing-avatars">
              {avatars.map((avatar, index) => <Avatar key={index} {...avatar} index={index} />)}
            </div>
            <p>Trusted by builders and businesses<br />on Arc Testnet</p>
          </div>
        </div>

        <div className="landing-mock" aria-hidden="true">
          <article className="mock-card mock-dashboard">
            <span className="mock-title">Dashboard</span>
            <div className="mock-stat">
              <small>Total protected</small>
              <strong>$8,420.00</strong>
              <span>Across 3 payments</span>
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
            <div className="mock-receipt-badge"><ShieldCheck size={20} /></div>
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
          <span>Powered by Circle</span>
          <div className="landing-stack-row">
            {stack.map((item) => (
              <div className="landing-stack-item" key={item.label}>{item.icon}<span>{item.label}</span></div>
            ))}
          </div>
        </div>
      </section>

      <section className="landing-features" id="features">
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

      <footer className="landing-footer">
        <div className="landing-footer-brand"><BrandMark /><span>Recourse</span></div>
        <p>Buyer protection for USDC payments on Arc. Testnet prototype.</p>
        <div className="landing-footer-links">
          <Link href="/dashboard">Launch App</Link>
          <Link href="/verify/5">Verifier</Link>
          <a href="https://github.com/frankolien/recourse" target="_blank" rel="noreferrer">GitHub</a>
        </div>
      </footer>
    </div>
  );
}
