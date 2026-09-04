"use client";

import { ArrowDownLeft, ArrowUpRight, BookUser, Loader2, ScrollText, Send, Users } from "lucide-react";
import Link from "next/link";
import {
  durationLabel,
  errorMessage,
  formatTime,
  formatUsdc,
  kindLabel,
  proposalSummary,
  shortAddress,
  TreasuryError,
  type AccountView,
  type LedgerEntry,
  type ProposalView,
} from "@/lib/treasury";
import { AddressChip, BackLink, Countdown, InlineError, KeyValue, PanelLoading, PermissionBadges, StatusPill, TreasuryFrame } from "./treasury-common";
import { useLedger, useProposals, useScheduled, useTreasuryAccount } from "./use-treasury";

function accountError(error: unknown): string {
  if (error instanceof TreasuryError && error.status === 403) return "You are not a member of this account. Link the address it names as a signer from the Treasury page.";
  if (error instanceof TreasuryError && error.status === 404) return "No treasury account at this address.";
  return errorMessage(error);
}

function SignersPanel({ account }: { account: AccountView }) {
  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div><h2>Signers</h2><p>{account.threshold} of {account.signers.length} must sign</p></div>
        <div className="treasury-actions"><Link href={`/treasury/${account.address}/rules`} className="page-cta ghost"><Users size={14} /> Change rules</Link></div>
      </div>
      <div className="treasury-rows">
        {account.signers.map((signer) => (
          <div className="treasury-row signers" key={signer.signerId}>
            <div className="treasury-cell">
              <strong>{signer.label}{signer.mine ? <span className="treasury-tag you">you</span> : null}</strong>
              {signer.address ? <AddressChip address={signer.address} /> : <small>{signer.kind} signer {shortAddress(signer.signerId)}</small>}
            </div>
            <PermissionBadges permissions={signer.permissions} />
          </div>
        ))}
      </div>
    </section>
  );
}

function RulesPanel({ account }: { account: AccountView }) {
  return (
    <section className="dash-panel">
      <div className="panel-heading compact"><h2>Rules</h2></div>
      <KeyValue
        items={[
          { label: "Threshold", value: `${account.threshold} of ${account.signers.length} signers` },
          {
            label: "Veto threshold",
            value: account.vetoThreshold === 0 ? `automatic, ${account.effectiveVetoThreshold} ${account.effectiveVetoThreshold === 1 ? "veto stops" : "vetoes stop"} a change` : `${account.vetoThreshold}`,
          },
          { label: "Config delay", value: durationLabel(account.configDelay) },
          { label: "Recovery delay", value: durationLabel(account.recoveryDelay) },
          { label: "Recovery co-sign delay", value: durationLabel(account.recoveryCoSignDelay) },
          { label: "Epoch", value: String(account.epoch) },
        ]}
      />
      <p className="treasury-hint">These are on-chain rules the account itself enforces. Changing them is a proposal that waits the config delay and can be vetoed.</p>
    </section>
  );
}

function QueuePanel({ address, proposals, loading, error }: { address: string; proposals: ProposalView[]; loading: boolean; error: unknown }) {
  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div><h2>Queue</h2><p>Proposals collecting signatures or waiting to run</p></div>
        <div className="treasury-actions"><Link href={`/treasury/${address}/pay`} className="page-cta ghost"><Send size={14} /> New payment</Link></div>
      </div>
      {loading ? (
        <div className="state-inline"><Loader2 size={18} className="spin" /><div><strong>Loading the queue</strong></div></div>
      ) : error ? (
        <InlineError message={errorMessage(error)} />
      ) : proposals.length === 0 ? (
        <p className="treasury-muted">Nothing waiting. A new payment or rule change appears here for the other signers.</p>
      ) : (
        <div className="treasury-rows">
          {proposals.map((proposal) => (
            <Link className="treasury-row queue link" href={`/treasury/${address}/proposals/${proposal.txHash}`} key={proposal.txHash}>
              <div className="treasury-cell">
                <strong>{kindLabel(proposal.kind)}</strong>
                <small>{proposalSummary(proposal)}</small>
              </div>
              <div className="treasury-cell num">
                <strong>{proposal.approvals} of {proposal.required}</strong>
                <small>{proposal.missing.length ? `waiting for ${proposal.missing.map((signer) => signer.label).join(", ")}` : "signed"}</small>
              </div>
              <div><StatusPill status={proposal.status} /></div>
              <ArrowUpRight size={16} />
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}

function ScheduledPanel({ address, items, loading }: { address: string; items: ProposalView[]; loading: boolean }) {
  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div><h2>Scheduled changes</h2><p>Rule changes waiting out their delay; a signer with veto can stop one</p></div>
        <div className="treasury-actions"><Link href={`/treasury/${address}/scheduled`} className="page-cta ghost">Open</Link></div>
      </div>
      {loading ? (
        <div className="state-inline"><Loader2 size={18} className="spin" /><div><strong>Loading scheduled changes</strong></div></div>
      ) : items.length === 0 ? (
        <p className="treasury-muted">No change is scheduled.</p>
      ) : (
        <div className="treasury-rows">
          {items.map((item) => (
            <Link className="treasury-row scheduled link" href={`/treasury/${address}/scheduled`} key={item.txHash}>
              <div className="treasury-cell">
                <strong>{kindLabel(item.kind)}</strong>
                <small>{proposalSummary(item)}</small>
              </div>
              <div className="treasury-cell">
                {item.scheduledReadyAt ? <Countdown target={item.scheduledReadyAt} /> : <strong>pending</strong>}
                <small>takes effect {formatTime(item.scheduledReadyAt)}</small>
              </div>
              <div className="treasury-cell num">
                <strong>{item.vetoes.length} of {item.effectiveVetoThreshold}</strong>
                <small>vetoes</small>
              </div>
              <ArrowUpRight size={16} />
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}

function LedgerPanel({ address, entries, loading }: { address: string; entries: LedgerEntry[]; loading: boolean }) {
  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div><h2>Recent ledger</h2><p>USDC in and out of the account</p></div>
        <div className="treasury-actions"><Link href={`/treasury/${address}/ledger`} className="page-cta ghost"><ScrollText size={14} /> Ledger</Link></div>
      </div>
      {loading ? (
        <div className="state-inline"><Loader2 size={18} className="spin" /><div><strong>Loading the ledger</strong></div></div>
      ) : entries.length === 0 ? (
        <p className="treasury-muted">No movements yet. Send USDC to the account address to fund it.</p>
      ) : (
        <div className="treasury-rows">
          {entries.slice(0, 10).map((entry) => (
            <div className="treasury-row recent" key={`${entry.tx}-${entry.logIndex}`}>
              <span className={entry.direction === "in" ? "treasury-direction in" : "treasury-direction out"}>
                {entry.direction === "in" ? <ArrowDownLeft size={14} /> : <ArrowUpRight size={14} />}
              </span>
              <div className="treasury-cell">
                <strong>{entry.counterpartyLabel ?? shortAddress(entry.counterparty)}</strong>
                <small>{entry.memo ?? formatTime(entry.blockTime)}</small>
              </div>
              <div className="treasury-cell num">
                <strong>{entry.direction === "in" ? "+" : "-"}{formatUsdc(entry.amount)}</strong>
                {entry.memo ? <small>{formatTime(entry.blockTime)}</small> : null}
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

export function TreasuryAccountPage({ address }: { address: string }) {
  const account = useTreasuryAccount(address);
  const queue = useProposals(address, ["open", "ready", "blocked"]);
  const scheduled = useScheduled(address);
  const ledger = useLedger(address, 10);

  if (account.isLoading) {
    return (
      <TreasuryFrame>
        <PanelLoading title="Loading the account" hint="Reading signers, rules and balance from the treasury service." />
      </TreasuryFrame>
    );
  }

  if (account.error || !account.data) {
    return (
      <TreasuryFrame>
        <header className="dash-header"><div><BackLink href="/treasury" label="Treasury" /><h1>Account</h1></div></header>
        <section className="dash-panel"><InlineError message={accountError(account.error)} /></section>
      </TreasuryFrame>
    );
  }

  const view = account.data;
  const openCount = queue.data?.length ?? 0;
  const scheduledItems = scheduled.data ?? [];

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <BackLink href="/treasury" label="Treasury" />
          <h1>{view.name}</h1>
          <p className="treasury-subtitle"><AddressChip address={view.address} /> {view.status !== "live" ? <span className="status-pill amber">{view.status}</span> : null}</p>
        </div>
        <div className="treasury-actions">
          <Link className="page-cta" href={`/treasury/${address}/pay`}><Send size={15} /> New payment</Link>
          <Link className="page-cta ghost" href={`/treasury/${address}/rules`}><Users size={15} /> Change rules</Link>
          <Link className="page-cta ghost" href={`/treasury/${address}/ledger#address-book`}><BookUser size={15} /> Address book</Link>
          <Link className="page-cta ghost" href={`/treasury/${address}/ledger`}><ScrollText size={15} /> Ledger</Link>
        </div>
      </header>

      {view.status === "deploying" ? (
        <div className="treasury-note warn">The creation transaction is still pending. The account becomes live once the receipt lands.</div>
      ) : view.status === "disabled" ? (
        <div className="treasury-note error">The service disabled this account after its hash self-check failed, so it accepts no writes. The account still works on chain with any other client.</div>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card"><span>Balance</span><strong>{formatUsdc(view.usdcBalance)}</strong><small>USDC on Arc testnet</small></article>
        <article className="metric-card"><span>Signers</span><strong>{view.threshold} of {view.signers.length}</strong><small>signatures to run a proposal</small></article>
        <article className="metric-card"><span>Open proposals</span><strong>{openCount}</strong><small>collecting signatures or ready</small></article>
        <article className="metric-card"><span>Scheduled changes</span><strong>{scheduledItems.length}</strong><small>waiting out the config delay</small></article>
      </section>

      <div className="two-col">
        <div className="page-stack">
          <QueuePanel address={address} proposals={queue.data ?? []} loading={queue.isLoading} error={queue.error} />
          <ScheduledPanel address={address} items={scheduledItems} loading={scheduled.isLoading} />
          <LedgerPanel address={address} entries={ledger.data ?? []} loading={ledger.isLoading} />
        </div>
        <div className="page-stack">
          <SignersPanel account={view} />
          <RulesPanel account={view} />
        </div>
      </div>
    </TreasuryFrame>
  );
}
