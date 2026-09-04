"use client";

import { useQueryClient } from "@tanstack/react-query";
import { Ban, Check, Loader2, Lock, Play, Trash2, X } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import {
  cancelProposal,
  deleteProposal,
  errorMessage,
  executeProposal,
  formatTime,
  hashMatches,
  kindLabel,
  type ProposalView,
} from "@/lib/treasury";
import { AddressChip, BackLink, CopyButton, Countdown, InlineError, KeyValue, PanelLoading, StatusPill, TreasuryFrame, TxChip } from "./treasury-common";
import { ConfirmControls } from "./treasury-sign";
import { treasuryKeys, useProposal, useTreasuryAccount } from "./use-treasury";

function ResultBanner({ address, proposal }: { address: string; proposal: ProposalView }) {
  switch (proposal.status) {
    case "executed":
      return (
        <div className="treasury-note ok">
          <Check size={15} />
          <span>Executed {formatTime(proposal.executedAt)}.{proposal.executedTx ? <> Transaction <TxChip hash={proposal.executedTx} /></> : null}</span>
        </div>
      );
    case "scheduled":
      return (
        <div className="treasury-note warn">
          <Lock size={15} />
          <span>
            Executed and now scheduled: this configuration change takes effect {proposal.scheduledReadyAt ? <>in <Countdown target={proposal.scheduledReadyAt} /> ({formatTime(proposal.scheduledReadyAt)})</> : "after its delay"}
            {proposal.executedTx ? <>, transaction <TxChip hash={proposal.executedTx} /></> : null}. {proposal.effectiveVetoThreshold} {proposal.effectiveVetoThreshold === 1 ? "veto stops" : "vetoes stop"} it.{" "}
            <Link href={`/treasury/${address}/scheduled`}>Open scheduled changes</Link>
          </span>
        </div>
      );
    case "executing":
      return <div className="treasury-note"><Loader2 size={15} className="spin" /><span>The relayer has sent the transaction and is waiting for the receipt.</span></div>;
    case "failed":
      return <div className="treasury-note error"><X size={15} /><span>The relayer&apos;s transaction reverted. The slot is still free, so the proposal can be tried again once the cause is fixed.</span></div>;
    case "vetoed":
      return <div className="treasury-note error"><Ban size={15} /><span>Vetoed by {proposal.vetoes.map((veto) => veto.label).join(", ") || "a signer"}.</span></div>;
    case "cancelled":
      return <div className="treasury-note error"><Ban size={15} /><span>Cancelled on chain.</span></div>;
    case "replaced":
      return <div className="treasury-note"><span>Another transaction took this slot, so this proposal can no longer run.</span></div>;
    case "stale":
      return <div className="treasury-note"><span>The account&apos;s epoch moved after this was proposed; its signatures no longer verify.</span></div>;
    case "expired":
      return <div className="treasury-note"><span>Expired {formatTime(proposal.validUntil)} without executing.</span></div>;
    default:
      return null;
  }
}

export function TreasuryProposalPage({ address, txHash }: { address: string; txHash: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const account = useTreasuryAccount(address);
  const proposal = useProposal(address, txHash);
  const [showRaw, setShowRaw] = useState(false);
  const [busy, setBusy] = useState<"execute" | "cancel" | "delete" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  function update(view: ProposalView) {
    queryClient.setQueryData(treasuryKeys.proposal(address, txHash), view);
    void queryClient.invalidateQueries({ queryKey: treasuryKeys.account(address) });
    void queryClient.invalidateQueries({ queryKey: ["treasury", "proposals", address] });
    void queryClient.invalidateQueries({ queryKey: treasuryKeys.scheduled(address) });
  }

  async function run(kind: "execute" | "cancel" | "delete") {
    setActionError(null);
    setBusy(kind);
    try {
      if (kind === "execute") {
        update(await executeProposal(address, txHash));
      } else if (kind === "cancel") {
        const cancel = await cancelProposal(address, txHash);
        update(cancel);
        router.push(`/treasury/${address}/proposals/${cancel.txHash}`);
      } else {
        await deleteProposal(address, txHash);
        void queryClient.invalidateQueries({ queryKey: ["treasury", "proposals", address] });
        router.push(`/treasury/${address}`);
      }
    } catch (cause) {
      setActionError(errorMessage(cause));
    } finally {
      setBusy(null);
    }
  }

  if (account.isLoading || proposal.isLoading) {
    return <TreasuryFrame><PanelLoading title="Loading the proposal" hint="Reading calls, signatures and the simulation." /></TreasuryFrame>;
  }
  if (account.error || !account.data || proposal.error || !proposal.data) {
    return (
      <TreasuryFrame>
        <header className="dash-header"><div><BackLink href={`/treasury/${address}`} label="Account" /><h1>Proposal</h1></div></header>
        <section className="dash-panel"><InlineError message={errorMessage(proposal.error ?? account.error)} /></section>
      </TreasuryFrame>
    );
  }

  const view = proposal.data;
  const hashOk = hashMatches(view);
  const canExecute = view.status === "ready";
  const canCancel = ["open", "ready", "blocked"].includes(view.status) && view.confirmations.length > 0;
  const canDelete = ["open", "ready", "blocked"].includes(view.status) && view.confirmations.length === 0;

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <BackLink href={`/treasury/${address}`} label={account.data.name} />
          <h1>{kindLabel(view.kind)} <span>proposal</span></h1>
          <p>
            Proposed {view.proposer ? `by ${view.proposer.name} ` : ""}{formatTime(view.createdAt)} · lane {view.nonceKey}, sequence {view.sequence} · valid until {formatTime(view.validUntil)}
          </p>
        </div>
        <div className="treasury-actions"><StatusPill status={view.status} /></div>
      </header>

      <ResultBanner address={address} proposal={view} />

      <div className="two-col">
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>What it does</h2><p>Decoded by the service from the calls the account will run</p></div>
              <div className="treasury-actions">
                <button type="button" className="page-cta ghost" onClick={() => setShowRaw((current) => !current)}>{showRaw ? "Hide raw calls" : "Show raw calls"}</button>
              </div>
            </div>
            <div className="treasury-calls">
              {view.decoded.map((call, index) => (
                <div className="treasury-call" key={`${call.to}-${index}`}>
                  <span className="rule-number">{index + 1}</span>
                  <div>
                    <strong>{call.summary}</strong>
                    <small><AddressChip address={call.to} label={call.label} /> selector {call.selector}{call.readable ? "" : " (not decoded)"}</small>
                  </div>
                </div>
              ))}
              {view.decoded.length === 0 ? <p className="treasury-muted">The service could not decode these calls; check the raw data.</p> : null}
            </div>
            {showRaw ? (
              <div className="treasury-raw">
                {view.calls.map((call, index) => (
                  <div key={index}>
                    <span>to</span><code>{call.to}</code>
                    <span>value</span><code>{call.value}</code>
                    <span>data</span><code>{call.data}</code>
                  </div>
                ))}
              </div>
            ) : null}
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Transaction hash</h2></div>
            <div className="treasury-hash">
              <code>{view.txHash}</code>
              <CopyButton value={view.txHash} title="Copy hash" />
            </div>
            <p className="treasury-hint">Compare this hash with what your wallet shows before you sign.</p>
            {!hashOk ? <InlineError message="The typed data in this proposal does not hash to its txHash. Signing is disabled until the service fixes it." /> : null}
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Approvals</h2><p>{view.approvals} of {view.required} needed</p></div>
            </div>
            <div className="treasury-rows">
              {view.confirmations.map((confirmation) => (
                <div className="treasury-row approvals" key={confirmation.signerId}>
                  <span className="treasury-direction in"><Check size={14} /></span>
                  <div className="treasury-cell">
                    <strong>{confirmation.label}</strong>
                    {confirmation.address ? <AddressChip address={confirmation.address} /> : null}
                  </div>
                  <div className="treasury-cell">
                    <strong>{confirmation.kind === "onchain" ? "approved on chain" : "signed"}</strong>
                    <small>{formatTime(confirmation.signedAt)}</small>
                  </div>
                </div>
              ))}
              {view.missing.map((signer) => (
                <div className="treasury-row approvals" key={signer.signerId}>
                  <span className="treasury-direction pending" />
                  <div className="treasury-cell">
                    <strong>{signer.label}{signer.mine ? <span className="treasury-tag you">you</span> : null}</strong>
                  </div>
                  <div className="treasury-cell"><strong className="treasury-muted">waiting</strong></div>
                </div>
              ))}
            </div>
            {view.blockedBy ? <p className="treasury-hint">Blocked behind proposal {view.blockedBy} in the same lane.</p> : null}
          </section>

          {hashOk ? <ConfirmControls account={account.data} proposal={view} onUpdated={update} /> : null}
        </div>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Rules</h2></div>
            {view.hardRules.length === 0 ? <p className="treasury-muted">No on-chain rule applies beyond the threshold.</p> : null}
            {view.hardRules.map((rule, index) => (
              <div className="treasury-rule" key={`${rule.rule}-${index}`}>
                <span className="treasury-rule-tag"><Lock size={11} /> On-chain rule</span>
                <p>{rule.text}</p>
              </div>
            ))}
            <div className={view.simulation ? (view.simulation.ok ? "treasury-sim ok" : "treasury-sim fail") : "treasury-sim"}>
              {view.simulation ? (
                view.simulation.ok ? (
                  <><Check size={14} /> <span>Simulation passed, checked {formatTime(view.simulation.checkedAt)}.</span></>
                ) : (
                  <><X size={14} /> <span>Simulation failed: {view.simulation.error ?? "the call reverts"}. Checked {formatTime(view.simulation.checkedAt)}.</span></>
                )
              ) : (
                <span>Not simulated yet.</span>
              )}
            </div>
          </section>

          {canExecute || canCancel || canDelete ? (
            <section className="dash-panel">
              <div className="panel-heading compact"><h2>Actions</h2></div>
              <div className="treasury-actions column">
                {canExecute ? (
                  <button type="button" className="page-cta" disabled={busy !== null} onClick={() => void run("execute")}>
                    {busy === "execute" ? <><Loader2 size={15} className="spin" /> Executing, waiting for the receipt</> : <><Play size={15} /> Execute</>}
                  </button>
                ) : null}
                {canCancel ? (
                  <button type="button" className="page-cta ghost" disabled={busy !== null} onClick={() => void run("cancel")}>
                    {busy === "cancel" ? <><Loader2 size={15} className="spin" /> Creating cancel proposal</> : <><Ban size={15} /> Cancel</>}
                  </button>
                ) : null}
                {canDelete ? (
                  <button type="button" className="page-cta ghost" disabled={busy !== null} onClick={() => void run("delete")}>
                    {busy === "delete" ? <><Loader2 size={15} className="spin" /> Deleting</> : <><Trash2 size={15} /> Delete</>}
                  </button>
                ) : null}
              </div>
              <p className="treasury-hint">
                {canExecute ? "Execute sends it through the relayer, which pays the gas and waits up to a minute for the receipt. " : ""}
                {canCancel ? "Cancel creates a new proposal carrying cancel(hash); once it collects the same threshold it kills this one at once, with no delay. " : ""}
                {canDelete ? "Delete removes it from the service while nobody has signed it." : ""}
              </p>
              <InlineError message={actionError} />
            </section>
          ) : null}

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Details</h2></div>
            <KeyValue
              items={[
                { label: "Lane", value: view.nonceKey },
                { label: "Sequence", value: String(view.sequence) },
                { label: "Nonce", value: view.nonce },
                { label: "Epoch", value: String(view.epoch) },
                { label: "Path", value: view.path },
                { label: "Valid after", value: view.validAfter ? formatTime(view.validAfter) : "immediately" },
                { label: "Valid until", value: formatTime(view.validUntil) },
                { label: "Account", value: <AddressChip address={view.account} /> },
              ]}
            />
          </section>
        </div>
      </div>
    </TreasuryFrame>
  );
}
