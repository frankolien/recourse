"use client";

import { ArrowUpRight, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { LiveNotice } from "@/components/live-notice";
import {
  type ApiPayment,
  formatDate,
  formatUsdc,
  getPayments,
  isDisputed,
  shortAddr,
  statusLabel,
  verdictOutcome,
} from "@/lib/api";
import { useLive } from "@/lib/use-live";

// Chain-direct demo verdicts, recomputable in the browser with no backend in the
// loop. Kept alongside the live list so the page always has a verifiable anchor.
const onchain = [
  { paymentId: 5, title: "Protected payment #5", outcome: "Refunded 100%", tone: "green", amount: "0.25 USDC" },
  { paymentId: 6, title: "Protected payment #6", outcome: "Denied", tone: "red", amount: "0.25 USDC" },
];

function rowStatus(p: ApiPayment): { label: string; tone: string } {
  return isDisputed(p) ? verdictOutcome(p) : statusLabel(p.status);
}

export function PaymentsPage() {
  const state = useLive(() => getPayments());
  const payments = state.data ?? [];

  const total = payments.reduce((sum, p) => sum + BigInt(p.amount || "0"), 0n);
  const protectedNow = payments.filter((p) => p.status === 1 && !isDisputed(p)).length;
  const settled = payments.filter((p) => p.status === 3).length;
  const openDisputes = payments.filter((p) => p.status === 2).length;

  const metrics = [
    { label: "Total volume", value: formatUsdc(total.toString()), sub: `${payments.length} payments`, tone: "" },
    { label: "Protected now", value: `${protectedNow}`, sub: "Held in escrow", tone: "up" },
    { label: "Settled", value: `${settled}`, sub: "Released", tone: "" },
    { label: "Open disputes", value: `${openDisputes}`, sub: "Awaiting verdict", tone: openDisputes ? "down" : "" },
  ];

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Payments</h1>
          <p>Every USDC payment indexed from Arc, protected end to end.</p>
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
          <div><h2>Recent payments</h2><p>Live onchain payments protected by an onchain policy</p></div>
          <Link href="/receipts">View receipts</Link>
        </div>
        <div className="records-table">
          <div className="records-head">
            <span>Merchant</span><span>Amount</span><span>Date</span><span>Status</span><span />
          </div>
          {payments.length > 0 ? (
            payments.map((p) => {
              const st = rowStatus(p);
              return (
                <Link className="records-row" href={isDisputed(p) ? `/verify/${p.paymentId}` : "/protection"} key={p.paymentId}>
                  <div className="records-id">
                    <span className="records-badge"><ShieldCheck size={16} /></span>
                    <div className="records-cell"><strong>{shortAddr(p.merchant)}</strong><small>Payment #{p.paymentId} · policy #{p.policyId}</small></div>
                  </div>
                  <div className="records-cell num"><strong>{formatUsdc(p.amount)}</strong><small>from {shortAddr(p.buyer)}</small></div>
                  <div className="records-cell"><strong>{formatDate(p.paidAt)}</strong></div>
                  <div><span className={`status-pill ${st.tone}`}>{st.label}</span></div>
                  <ArrowUpRight size={16} />
                </Link>
              );
            })
          ) : (
            <LiveNotice state={state} emptyTitle="No payments indexed" emptyHint="Once the indexer catches up with Arc, onchain payments appear here." />
          )}
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
