"use client";

import { ArrowUpRight, Download, FileText, ReceiptText } from "lucide-react";
import Link from "next/link";
import { LiveNotice } from "@/components/live-notice";
import { type ApiPayment, formatDate, formatUsdc, getPayments, isDisputed, shortAddr, verdictOutcome } from "@/lib/api";
import { useLive } from "@/lib/use-live";

function receiptKind(p: ApiPayment): { kind: string; tone: string } {
  if (!isDisputed(p)) return { kind: "Purchase", tone: "neutral" };
  const o = verdictOutcome(p);
  if (o.tone === "green") return { kind: "Refund", tone: "green" };
  if (o.tone === "red") return { kind: "Charge held", tone: "red" };
  return { kind: "Partial refund", tone: "amber" };
}

export function ReceiptsPage() {
  const state = useLive(() => getPayments());
  const receipts = state.data ?? [];

  const total = receipts.reduce((sum, p) => sum + BigInt(p.amount || "0"), 0n);
  const proofs = receipts.filter(isDisputed).length;

  const metrics = [
    { label: "Receipts", value: `${receipts.length}`, sub: "All time" },
    { label: "Total volume", value: formatUsdc(total.toString()), sub: `${receipts.length} payments` },
    { label: "Onchain proofs", value: `${proofs}`, sub: "Recomputable" },
  ];

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
          {receipts.length > 0 ? (
            receipts.map((p) => {
              const rk = receiptKind(p);
              return (
                <Link className="records-row" href={isDisputed(p) ? `/verify/${p.paymentId}` : "/payments"} key={p.paymentId}>
                  <div className="records-id">
                    <span className="records-badge">{rk.tone === "green" ? <ReceiptText size={16} /> : <FileText size={16} />}</span>
                    <div className="records-cell"><strong>{shortAddr(p.merchant)}</strong><small>Payment #{p.paymentId}</small></div>
                  </div>
                  <div className="records-cell num"><strong>{formatUsdc(p.amount)}</strong></div>
                  <div className="records-cell"><strong>{formatDate(p.paidAt)}</strong></div>
                  <div><span className={`status-pill ${rk.tone}`}>{rk.kind}</span></div>
                  <ArrowUpRight size={16} />
                </Link>
              );
            })
          ) : (
            <LiveNotice state={state} emptyTitle="No receipts yet" emptyHint="Indexed payments and their refunds appear here." />
          )}
        </div>
      </section>
    </div>
  );
}
