import {
  ArrowUpRight,
  Download,
  FileText,
  ReceiptText,
} from "lucide-react";
import Link from "next/link";

const metrics = [
  { label: "Receipts", value: "6", sub: "All time" },
  { label: "This month", value: "$1,240.00", sub: "5 payments" },
  { label: "Onchain proofs", value: "2", sub: "Recomputable" },
];

const receipts = [
  { id: "RCP-286", merchant: "CloudCompute", amount: "$24.00", date: "20 Jul 2026", kind: "Purchase", tone: "neutral", href: "/payments" },
  { id: "RCP-285", merchant: "FileStore", amount: "$120.00", date: "18 Jul 2026", kind: "Purchase", tone: "neutral", href: "/payments" },
  { id: "RCP-005", merchant: "Acme Store", amount: "0.25 USDC", date: "20 Jul 2026", kind: "Refund", tone: "green", href: "/verify/5" },
  { id: "RCP-006", merchant: "Acme Store", amount: "0.25 USDC", date: "20 Jul 2026", kind: "Charge held", tone: "red", href: "/verify/6" },
  { id: "RCP-280", merchant: "PrintWorks", amount: "$44.00", date: "9 Jul 2026", kind: "Purchase", tone: "neutral", href: "/payments" },
];

export function ReceiptsPage() {
  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Receipts</h1>
          <p>A record of every payment, refund, and settlement, with a proof link where one exists.</p>
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

      <section className="dash-panel">
        <div className="panel-heading">
          <div><h2>All receipts</h2><p>Purchases, refunds, and held charges</p></div>
          <button className="page-cta ghost"><Download size={15} /> Export CSV</button>
        </div>
        <div className="records-table">
          <div className="records-head">
            <span>Receipt</span><span>Amount</span><span>Date</span><span>Type</span><span /></div>
          {receipts.map((item) => (
            <Link className="records-row" href={item.href} key={item.id}>
              <div className="records-id">
                <span className="records-badge">{item.tone === "green" ? <ReceiptText size={16} /> : <FileText size={16} />}</span>
                <div className="records-cell"><strong>{item.merchant}</strong><small>{item.id}</small></div>
              </div>
              <div className="records-cell num"><strong>{item.amount}</strong></div>
              <div className="records-cell"><strong>{item.date}</strong></div>
              <div><span className={`status-pill ${item.tone}`}>{item.kind}</span></div>
              <ArrowUpRight size={16} />
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
