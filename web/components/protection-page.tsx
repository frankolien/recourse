import {
  Check,
  ChevronRight,
  Cloud,
  FileText,
  Info,
  ShieldCheck,
  Zap,
} from "lucide-react";
import Link from "next/link";

const metrics = [
  { label: "Active protections", value: "3", sub: "Across 3 merchants" },
  { label: "Total protected", value: "$640.00", sub: "Held in escrow" },
  { label: "Average window", value: "30 days", sub: "Until auto release" },
];

const active = [
  { merchant: "CloudCompute", product: "API Credits Pack", amount: "$24.00", units: "24.00 USDC", ends: "3 Aug 2026, 4:30 PM", remaining: "in 13 days", progress: 70, icon: <Cloud size={18} />, tone: "cloud" },
  { merchant: "FileStore", product: "Pro Plan Monthly", amount: "$120.00", units: "120.00 USDC", ends: "15 Aug 2026, 10:00 AM", remaining: "in 25 days", progress: 45, icon: <FileText size={18} />, tone: "file" },
  { merchant: "DesignVault", product: "Premium Assets", amount: "$320.00", units: "320.00 USDC", ends: "28 Aug 2026, 11:59 PM", remaining: "in 38 days", progress: 30, icon: <Zap size={18} />, tone: "design" },
];

const released = [
  { merchant: "PrintWorks", product: "Business Cards", amount: "$44.00", date: "9 Jul 2026", status: "Released", tone: "neutral" },
  { merchant: "Acme Store", product: "Protected payment #5", amount: "0.25 USDC", date: "20 Jul 2026", status: "Refunded", tone: "green", href: "/verify/5" },
];

export function ProtectionPage() {
  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Protection</h1>
          <p>Funds stay in escrow, earning yield, until the dispute window closes or a verdict lands.</p>
        </div>
      </header>

      <section className="metric-grid cols-3">
        {metrics.map((metric) => (
          <article className="metric-card" key={metric.label}>
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
            <small>{metric.sub}</small>
          </article>
        ))}
      </section>

      <section className="dash-panel protections-panel">
        <div className="panel-heading">
          <div><h2>Active protections</h2><p>Payments currently protected by Recourse</p></div>
          <Link href="/payments">View payments</Link>
        </div>
        <div className="protection-table">
          <div className="protection-head">
            <span>Merchant</span><span>Amount</span><span>Protection ends</span><span>Status</span><span>Progress</span><span />
          </div>
          {active.map((item) => (
            <Link className="protection-row" href="/disputes" key={item.merchant}>
              <div className="merchant-cell"><span className={`merchant-icon ${item.tone}`}>{item.icon}</span><span><strong>{item.merchant}</strong><small>{item.product}</small></span></div>
              <div><strong>{item.amount}</strong><small>{item.units}</small></div>
              <div><strong>{item.ends}</strong><small>{item.remaining}</small></div>
              <div><span className="active-status"><ShieldCheck size={14} /> Active</span></div>
              <div className="progress-cell"><span><i style={{ width: `${item.progress}%` }} /></span><small>{item.progress}% of window</small></div>
              <ChevronRight size={16} />
            </Link>
          ))}
        </div>
      </section>

      <section className="dash-panel">
        <div className="panel-heading">
          <div><h2>Recently released</h2><p>Protection windows that have closed or resolved</p></div>
          <Link href="/receipts">Receipts</Link>
        </div>
        <div className="records-table">
          <div className="records-head">
            <span>Merchant</span><span>Amount</span><span>Date</span><span>Outcome</span><span />
          </div>
          {released.map((item) => {
            const inner = (
              <>
                <div className="records-id">
                  <span className="records-badge"><Check size={16} /></span>
                  <div className="records-cell"><strong>{item.merchant}</strong><small>{item.product}</small></div>
                </div>
                <div className="records-cell num"><strong>{item.amount}</strong></div>
                <div className="records-cell"><strong>{item.date}</strong></div>
                <div><span className={`status-pill ${item.tone}`}>{item.status}</span></div>
                <ChevronRight size={16} />
              </>
            );
            return item.href
              ? <Link className="records-row" href={item.href} key={item.product}>{inner}</Link>
              : <div className="records-row" key={item.product}>{inner}</div>;
          })}
        </div>
      </section>

      <div className="panel-note">
        <Info size={16} />
        <span>Protection is deterministic. When a dispute is filed, the same policy engine runs onchain and in your browser, so the refund outcome can be recomputed by anyone. Try it on the <Link href="/verify/5" style={{ color: "inherit", fontWeight: 600, textDecoration: "underline" }}>public verifier</Link>.</span>
      </div>
    </div>
  );
}
