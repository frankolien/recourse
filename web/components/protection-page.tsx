"use client";

import { Check, ChevronRight, Info, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { LiveNotice } from "@/components/live-notice";
import {
  type ApiPayment,
  type ApiPolicy,
  formatDate,
  formatUsdc,
  getPayments,
  getPolicies,
  isDisputed,
  shortAddr,
  verdictOutcome,
} from "@/lib/api";
import { useLive } from "@/lib/use-live";

interface ProtectionData {
  payments: ApiPayment[];
  policies: ApiPolicy[];
}

function windowFor(policies: ApiPolicy[], policyId: number): number {
  return policies.find((p) => p.policyId === policyId)?.disputeWindow ?? 0;
}

export function ProtectionPage() {
  const state = useLive<ProtectionData>(() =>
    Promise.all([getPayments(), getPolicies()]).then(([payments, policies]) => ({ payments, policies })),
  );
  const payments = state.data?.payments ?? [];
  const policies = state.data?.policies ?? [];

  const active = payments.filter((p) => p.status === 1 && !isDisputed(p));
  const released = payments.filter((p) => p.status === 3 || isDisputed(p));
  const totalProtected = active.reduce((sum, p) => sum + BigInt(p.amount || "0"), 0n);
  const nowSecs = Math.floor(Date.now() / 1000);

  const firstPolicy = policies[0];
  const metrics = [
    { label: "Active protections", value: `${active.length}`, sub: "Held in escrow" },
    { label: "Total protected", value: formatUsdc(totalProtected.toString()), sub: "Across active payments" },
    { label: "Onchain policy", value: firstPolicy ? `#${firstPolicy.policyId}` : "-", sub: "Immutable rule set" },
  ];

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
          {active.length > 0 ? (
            active.map((p) => {
              const window = windowFor(policies, p.policyId);
              const ends = p.paidAt + window;
              const elapsed = window > 0 ? Math.min(Math.max((nowSecs - p.paidAt) / window, 0), 1) : 0;
              const progress = Math.round(elapsed * 100);
              return (
                <Link className="protection-row" href={`/verify/${p.paymentId}`} key={p.paymentId}>
                  <div className="merchant-cell"><span className="merchant-icon cloud"><ShieldCheck size={18} /></span><span><strong>{shortAddr(p.merchant)}</strong><small>Payment #{p.paymentId}</small></span></div>
                  <div><strong>{formatUsdc(p.amount)}</strong><small>from {shortAddr(p.buyer)}</small></div>
                  <div><strong>{window > 0 ? formatDate(ends) : "Open"}</strong><small>{window > 0 ? `${Math.round(window / 86400)} day window` : "No window"}</small></div>
                  <div><span className="active-status"><ShieldCheck size={14} /> Active</span></div>
                  <div className="progress-cell"><span><i style={{ width: `${progress}%` }} /></span><small>{progress}% of window</small></div>
                  <ChevronRight size={16} />
                </Link>
              );
            })
          ) : (
            <LiveNotice state={state} emptyTitle="No active protections" emptyHint="Protected payments held in escrow will appear here." />
          )}
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
          {released.length > 0 ? (
            released.map((p) => {
              const outcome = isDisputed(p) ? verdictOutcome(p) : { label: "Released", tone: "neutral" };
              return (
                <Link className="records-row" href={isDisputed(p) ? `/verify/${p.paymentId}` : "/receipts"} key={p.paymentId}>
                  <div className="records-id">
                    <span className="records-badge"><Check size={16} /></span>
                    <div className="records-cell"><strong>{shortAddr(p.merchant)}</strong><small>Payment #{p.paymentId}</small></div>
                  </div>
                  <div className="records-cell num"><strong>{formatUsdc(p.amount)}</strong></div>
                  <div className="records-cell"><strong>{formatDate(p.paidAt)}</strong></div>
                  <div><span className={`status-pill ${outcome.tone}`}>{outcome.label}</span></div>
                  <ChevronRight size={16} />
                </Link>
              );
            })
          ) : (
            <LiveNotice state={state} emptyTitle="Nothing released yet" emptyHint="Settled and resolved payments will appear here." />
          )}
        </div>
      </section>

      <div className="panel-note">
        <Info size={16} />
        <span>Protection is deterministic. When a dispute is filed, the same policy engine runs onchain and in your browser, so the refund outcome can be recomputed by anyone. Try it on the <Link href="/verify/5" style={{ color: "inherit", fontWeight: 600, textDecoration: "underline" }}>public verifier</Link>.</span>
      </div>
    </div>
  );
}
