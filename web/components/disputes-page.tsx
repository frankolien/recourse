"use client";

import { ChevronRight, FlaskConical, LockKeyhole, ShieldCheck, XCircle } from "lucide-react";
import Link from "next/link";
import { LiveNotice } from "@/components/live-notice";
import { CLAIM_TYPES, formatDate, formatUsdc, getDisputes, shortAddr, verdictOutcome } from "@/lib/api";
import { useLive } from "@/lib/use-live";

export function DisputesPage() {
  const state = useLive(() => getDisputes());
  const disputes = state.data ?? [];

  const open = disputes.filter((p) => p.status === 2);
  const resolved = disputes.filter((p) => p.status === 3);
  const openCase = open[0];

  const metrics = [
    { label: "Open", value: `${open.length}`, sub: open.length ? "Awaiting verdict" : "All clear" },
    { label: "Filed", value: `${disputes.length}`, sub: "Total claims" },
    { label: "Resolved", value: `${resolved.length}`, sub: "With onchain verdict" },
  ];

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Disputes</h1>
          <p>Track every filed claim and its verdict. Outcomes are decided by policy, not by support.</p>
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
              <div><h2>Open dispute</h2><p>Claims filed and awaiting a verdict</p></div>
              {openCase && <Link href={`/verify/${openCase.paymentId}`}>Open verifier</Link>}
            </div>
            {openCase ? (
              <div className="dispute-row">
                <div className="dispute-order">
                  <span className="dispute-icon"><LockKeyhole size={17} /></span>
                  <div><strong>Payment #{openCase.paymentId}</strong><small>vs {shortAddr(openCase.merchant)}</small><b>Awaiting verdict</b></div>
                </div>
                <div className="dispute-info"><span>Issue</span><strong>{CLAIM_TYPES[openCase.claimType] ?? "Other"}</strong><small>Filed on<br />{formatDate(openCase.filedAt)}</small></div>
                <div className="dispute-info"><span>Amount</span><strong>{formatUsdc(openCase.amount)}</strong><small>Held in escrow</small></div>
                <div className="dispute-info due"><span>Next step</span><strong>Attestor verdict</strong><small>Recompute it live on the verifier</small></div>
              </div>
            ) : (
              <LiveNotice state={state} emptyTitle="No open disputes" emptyHint="Every filed claim has reached an onchain verdict." />
            )}
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Dispute history</h2><p>Filed claims and their onchain verdicts</p></div>
            </div>
            <div className="records-table">
              <div className="records-head">
                <span>Order</span><span>Amount</span><span>Issue</span><span>Verdict</span><span />
              </div>
              {disputes.length > 0 ? (
                disputes.map((p) => {
                  const outcome = verdictOutcome(p);
                  return (
                    <Link className="records-row" href={`/verify/${p.paymentId}`} key={p.paymentId}>
                      <div className="records-id">
                        <span className="records-badge">{outcome.tone === "red" ? <XCircle size={16} /> : <ShieldCheck size={16} />}</span>
                        <div className="records-cell"><strong>{shortAddr(p.merchant)}</strong><small>Payment #{p.paymentId}</small></div>
                      </div>
                      <div className="records-cell num"><strong>{formatUsdc(p.amount)}</strong></div>
                      <div className="records-cell"><strong>{CLAIM_TYPES[p.claimType] ?? "Other"}</strong></div>
                      <div><span className={`status-pill ${outcome.tone}`}>{outcome.label}</span></div>
                      <ChevronRight size={16} />
                    </Link>
                  );
                })
              ) : (
                <LiveNotice state={state} emptyTitle="No disputes filed" emptyHint="Filed claims and their verdicts will appear here." />
              )}
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
