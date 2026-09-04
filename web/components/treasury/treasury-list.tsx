"use client";

import { ArrowUpRight, Landmark, Plus } from "lucide-react";
import Link from "next/link";
import { errorMessage, formatUsdc } from "@/lib/treasury";
import { AddressChip, InlineError, PanelLoading, TreasuryFrame } from "./treasury-common";
import { SigningKeysPanel } from "./treasury-keys";
import { useAccounts } from "./use-treasury";

export function TreasuryListPage() {
  const accounts = useAccounts();
  const rows = accounts.data ?? [];

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <h1>Treasury</h1>
          <p>Shared USDC accounts on Arc that only their members control.</p>
        </div>
        <Link className="page-cta" href="/treasury/new"><Plus size={15} /> New account</Link>
      </header>

      {accounts.isLoading ? (
        <PanelLoading title="Loading your accounts" hint="Reading the treasury service." />
      ) : accounts.error ? (
        <section className="dash-panel"><InlineError message={errorMessage(accounts.error)} /></section>
      ) : rows.length === 0 ? (
        <section className="dash-panel treasury-empty">
          <Landmark size={22} />
          <div>
            <strong>No treasury accounts yet</strong>
            <p>
              A treasury account is a USDC account on Arc owned by a team, where a payment or a rule change runs only after enough of the members have signed it.
              Create one, name its signers and the threshold, and it exists on chain in a few seconds at an address that can take deposits right away.
            </p>
          </div>
          <Link className="page-cta ghost" href="/treasury/new"><Plus size={15} /> New account</Link>
        </section>
      ) : (
        <section className="dash-panel">
          <div className="panel-heading">
            <div><h2>Accounts</h2><p>Every account you created or sign for</p></div>
          </div>
          <div className="treasury-rows">
            <div className="treasury-row accounts head">
              <span>Account</span><span>Balance</span><span>Signers</span><span>Open</span><span>Scheduled</span><span />
            </div>
            {rows.map((row) => (
              <div className="treasury-row accounts" key={row.address}>
                <div className="treasury-cell">
                  <Link href={`/treasury/${row.address}`} className="treasury-row-title">{row.name}</Link>
                  <AddressChip address={row.address} />
                  {row.status !== "live" ? <small>{row.status}</small> : null}
                </div>
                <div className="treasury-cell num"><strong>{formatUsdc(row.usdcBalance)}</strong></div>
                <div className="treasury-cell"><strong>{row.threshold} of {row.signerCount}</strong><small>signatures to run</small></div>
                <div className="treasury-cell num"><strong>{row.openProposals}</strong><small>proposals</small></div>
                <div className="treasury-cell num"><strong>{row.scheduledChanges}</strong><small>changes</small></div>
                <Link href={`/treasury/${row.address}`} className="treasury-icon-button" aria-label={`Open ${row.name}`}><ArrowUpRight size={16} /></Link>
              </div>
            ))}
          </div>
        </section>
      )}

      <SigningKeysPanel />
    </TreasuryFrame>
  );
}
