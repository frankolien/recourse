import {
  ArrowUpRight,
  Cloud,
  FileText,
  Package,
  ShieldCheck,
  Zap,
} from "lucide-react";
import Link from "next/link";

const metrics = [
  { label: "Total volume", value: "$1,240.00", sub: "This month", tone: "" },
  { label: "Protected now", value: "$640.00", sub: "3 payments", tone: "up" },
  { label: "Settled", value: "$580.00", sub: "Released to merchants", tone: "" },
  { label: "Open disputes", value: "1", sub: "Awaiting evidence", tone: "down" },
];

const payments = [
  { id: "RC-286", merchant: "CloudCompute", product: "API Credits Pack", amount: "$24.00", units: "24.00 USDC", date: "20 Jul 2026", status: "Protected", tone: "green", href: "/protection", icon: <Cloud size={16} /> },
  { id: "RC-285", merchant: "FileStore", product: "Pro Plan Monthly", amount: "$120.00", units: "120.00 USDC", date: "18 Jul 2026", status: "Protected", tone: "green", href: "/protection", icon: <FileText size={16} /> },
  { id: "RC-283", merchant: "DesignVault", product: "Premium Assets", amount: "$320.00", units: "320.00 USDC", date: "15 Jul 2026", status: "Protected", tone: "green", href: "/protection", icon: <Zap size={16} /> },
  { id: "RC-280", merchant: "PrintWorks", product: "Business Cards", amount: "$44.00", units: "44.00 USDC", date: "9 Jul 2026", status: "Settled", tone: "neutral", href: "/receipts", icon: <Package size={16} /> },
];

const onchain = [
  { paymentId: 5, title: "Protected payment #5", outcome: "Refunded 100%", tone: "green", amount: "0.25 USDC" },
  { paymentId: 6, title: "Protected payment #6", outcome: "Denied", tone: "red", amount: "0.25 USDC" },
];

export function PaymentsPage() {
  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Payments</h1>
          <p>Every USDC payment you have made through Recourse, protected end to end.</p>
        </div>
      </header>

      <section className="metric-grid">
        {metrics.map((metric) => (
          <article className="metric-card" key={metric.label}>
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
            <small className={metric.tone}>{metric.sub}</small>
          </article>
        ))}
      </section>

      <section className="dash-panel">
        <div className="panel-heading">
          <div><h2>Recent payments</h2><p>Product purchases protected by an onchain policy</p></div>
          <Link href="/receipts">View receipts</Link>
        </div>
        <div className="records-table">
          <div className="records-head">
            <span>Merchant</span><span>Amount</span><span>Date</span><span>Status</span><span />
          </div>
          {payments.map((payment) => (
            <Link className="records-row" href={payment.href} key={payment.id}>
              <div className="records-id">
                <span className="records-badge">{payment.icon}</span>
                <div className="records-cell"><strong>{payment.merchant}</strong><small>{payment.id} · {payment.product}</small></div>
              </div>
              <div className="records-cell num"><strong>{payment.amount}</strong><small>{payment.units}</small></div>
              <div className="records-cell"><strong>{payment.date}</strong></div>
              <div><span className={`status-pill ${payment.tone}`}>{payment.status}</span></div>
              <ArrowUpRight size={16} />
            </Link>
          ))}
        </div>
      </section>

      <section className="dash-panel">
        <div className="panel-heading">
          <div><h2>Verifiable on Arc testnet</h2><p>These verdicts can be recomputed by anyone, with no backend in the loop</p></div>
          <Link href="/verify/5">Open verifier</Link>
        </div>
        <div className="records-table">
          {onchain.map((item) => (
            <Link className="records-row" href={`/verify/${item.paymentId}`} key={item.paymentId}>
              <div className="records-id">
                <span className="records-badge"><ShieldCheck size={16} /></span>
                <div className="records-cell"><strong>{item.title}</strong><small>Live eth_call plus in-browser recompute</small></div>
              </div>
              <div className="records-cell num"><strong>{item.amount}</strong><small>Onchain amount</small></div>
              <div className="records-cell"><strong>Arc testnet</strong></div>
              <div><span className={`status-pill ${item.tone}`}>{item.outcome}</span></div>
              <ArrowUpRight size={16} />
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
