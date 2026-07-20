import {
  ChevronRight,
  FlaskConical,
  LockKeyhole,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import Link from "next/link";

const metrics = [
  { label: "Open", value: "1", sub: "Needs your evidence" },
  { label: "Awaiting verdict", value: "0", sub: "Attestor idle" },
  { label: "Resolved", value: "4", sub: "Last 30 days" },
];

const history = [
  { id: "RC-278", merchant: "MegaStore", issue: "Item not as described", amount: "0.25 USDC", outcome: "Refunded", tone: "green", href: "/verify/5" },
  { id: "RC-271", merchant: "QuickShip", issue: "Wrong item", amount: "0.25 USDC", outcome: "Denied", tone: "red", href: "/verify/6" },
  { id: "RC-260", merchant: "BrightGoods", issue: "Damaged on arrival", amount: "$60.00", outcome: "Partial 50%", tone: "amber" },
  { id: "RC-244", merchant: "PixelPrints", issue: "Not delivered", amount: "$18.00", outcome: "Refunded", tone: "green" },
];

export function DisputesPage() {
  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Disputes</h1>
          <p>Track every open case and its verdict. Outcomes are decided by policy, not by support.</p>
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

      <div className="two-col">
        <div className="page-stack">
          <section className="dash-panel disputes-panel">
            <div className="panel-heading compact">
              <div><h2>Open dispute</h2><p>Submit evidence before the window closes</p></div>
              <Link href="/verify/5">Open verifier</Link>
            </div>
            <div className="dispute-row">
              <div className="dispute-order"><span className="dispute-icon"><LockKeyhole size={17} /></span><div><strong>Order #RC-284</strong><small>vs MegaStore</small><b>Evidence required</b></div></div>
              <div className="dispute-info"><span>Issue</span><strong>Service was not delivered</strong><small>Requested on<br />20 Jul 2026, 9:18 AM</small></div>
              <div className="dispute-info due"><span>Evidence due</span><strong>Today, 5:00 PM</strong><small>in 5h 42m</small></div>
              <div className="dispute-timeline">
                <div className="timeline-line"><i className="done" /><i className="review" /><i /><i /></div>
                <div className="timeline-labels"><span><b>Submitted</b><small>20 Jul, 9:18 AM</small></span><span><b>Under review</b><small>Waiting for evidence</small></span><span><b>Decision</b><small>Pending</small></span><span><b>Resolved</b><small>Pending</small></span></div>
              </div>
            </div>
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Dispute history</h2><p>Resolved cases and their onchain verdicts</p></div>
            </div>
            <div className="records-table">
              <div className="records-head">
                <span>Order</span><span>Amount</span><span>Issue</span><span>Verdict</span><span />
              </div>
              {history.map((item) => {
                const inner = (
                  <>
                    <div className="records-id">
                      <span className="records-badge">{item.tone === "red" ? <XCircle size={16} /> : <ShieldCheck size={16} />}</span>
                      <div className="records-cell"><strong>{item.merchant}</strong><small>{item.id}</small></div>
                    </div>
                    <div className="records-cell num"><strong>{item.amount}</strong></div>
                    <div className="records-cell"><strong>{item.issue}</strong></div>
                    <div><span className={`status-pill ${item.tone}`}>{item.outcome}</span></div>
                    <ChevronRight size={16} />
                  </>
                );
                return item.href
                  ? <Link className="records-row" href={item.href} key={item.id}>{inner}</Link>
                  : <div className="records-row" key={item.id}>{inner}</div>;
              })}
            </div>
          </section>
        </div>

        <section className="dash-panel">
          <div className="panel-heading compact"><h2>How a verdict is reached</h2></div>
          <ol className="how-steps">
            <li><span><FlaskConical size={15} /></span><div><strong>Policy runs</strong><p>The immutable rule set pinned to the payment evaluates the claim and evidence.</p></div></li>
            <li><span><ShieldCheck size={15} /></span><div><strong>Attestor signs</strong><p>Objective inputs, such as delivery, are attested with an EIP-712 signature.</p></div></li>
            <li><span><LockKeyhole size={15} /></span><div><strong>Escrow settles</strong><p>The refund and merchant split settle atomically from the escrow balance.</p></div></li>
          </ol>
          <Link className="page-cta ghost" href="/verify/5"><FlaskConical size={15} /> Recompute a verdict</Link>
        </section>
      </div>
    </div>
  );
}
