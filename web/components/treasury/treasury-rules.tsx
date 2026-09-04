"use client";

import { Loader2, Plus, RotateCcw, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import {
  durationLabel,
  errorMessage,
  isValidAddress,
  proposeSigners,
  shortAddress,
  type AccountView,
  type SignersProposalBody,
} from "@/lib/treasury";
import { AddressChip, BackLink, InlineError, PanelLoading, PermissionBadges, TreasuryFrame } from "./treasury-common";
import { DurationField, SignerRows, newSignerDraft, permissionsOf, type SignerDraft } from "./treasury-forms";
import { useTreasuryAccount } from "./use-treasury";

interface RulesDraft {
  removed: string[];
  added: SignerDraft[];
  threshold: number;
  vetoThreshold: number;
  configDelay: number;
  recoveryDelay: number;
  recoveryCoSignDelay: number;
}

function draftFrom(account: AccountView): RulesDraft {
  return {
    removed: [],
    added: [],
    threshold: account.threshold,
    vetoThreshold: account.vetoThreshold,
    configDelay: account.configDelay,
    recoveryDelay: account.recoveryDelay,
    recoveryCoSignDelay: account.recoveryCoSignDelay,
  };
}

function RulesEditor({ address, account }: { address: string; account: AccountView }) {
  const router = useRouter();
  const [draft, setDraft] = useState<RulesDraft>(() => draftFrom(account));
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const remaining = account.signers.filter((signer) => !draft.removed.includes(signer.signerId));
  const approversAfter = remaining.filter((signer) => signer.permissions.includes("approve")).length + draft.added.filter((signer) => signer.approve).length;
  const delaysChanged =
    draft.configDelay !== account.configDelay || draft.recoveryDelay !== account.recoveryDelay || draft.recoveryCoSignDelay !== account.recoveryCoSignDelay;
  const changed =
    draft.removed.length > 0 || draft.added.length > 0 || draft.threshold !== account.threshold || draft.vetoThreshold !== account.vetoThreshold || delaysChanged;

  function toggleRemove(signerId: string) {
    setDraft((current) => ({
      ...current,
      removed: current.removed.includes(signerId) ? current.removed.filter((id) => id !== signerId) : [...current.removed, signerId],
    }));
  }

  function patchAdded(key: number, change: Partial<SignerDraft>) {
    setDraft((current) => ({ ...current, added: current.added.map((signer) => (signer.key === key ? { ...signer, ...change } : signer)) }));
  }

  function validate(): SignersProposalBody | string {
    if (!changed) return "Nothing has changed yet.";
    const seen = new Set(account.signers.map((signer) => signer.address?.toLowerCase()).filter((value): value is string => Boolean(value)));
    for (const [index, signer] of draft.added.entries()) {
      if (!isValidAddress(signer.address)) return `New signer ${index + 1} needs a valid address.`;
      const lower = signer.address.toLowerCase();
      if (seen.has(lower)) return `New signer ${index + 1} is already a signer or listed twice.`;
      seen.add(lower);
      if (!signer.approve && !signer.veto) return `New signer ${index + 1} needs at least one permission.`;
    }
    if (draft.threshold < 1 || draft.threshold > approversAfter) return `The threshold must be between 1 and ${approversAfter}, the approving signers left after this change.`;
    const body: SignersProposalBody = {
      add: draft.added.map((signer, index) => ({
        kind: "ecdsa",
        address: signer.address.toLowerCase(),
        label: signer.label.trim() || `Signer ${account.signers.length + index + 1}`,
        permissions: permissionsOf(signer),
      })),
      remove: draft.removed,
      replace: [],
    };
    if (draft.threshold !== account.threshold) body.threshold = draft.threshold;
    if (draft.vetoThreshold !== account.vetoThreshold) body.vetoThreshold = draft.vetoThreshold;
    if (delaysChanged) {
      body.delays = { configDelay: draft.configDelay, recoveryDelay: draft.recoveryDelay, recoveryCoSignDelay: draft.recoveryCoSignDelay };
    }
    return body;
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const body = validate();
    if (typeof body === "string") {
      setError(body);
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const view = await proposeSigners(address, body);
      router.push(`/treasury/${address}/proposals/${view.txHash}`);
    } catch (cause) {
      setError(errorMessage(cause));
      setSubmitting(false);
    }
  }

  return (
    <form className="two-col" onSubmit={(event) => void submit(event)}>
      <div className="page-stack">
        <section className="dash-panel">
          <div className="panel-heading">
            <div><h2>Current signers</h2><p>Mark a signer for removal; it leaves once the change takes effect</p></div>
          </div>
          <div className="treasury-rows">
            {account.signers.map((signer) => {
              const removed = draft.removed.includes(signer.signerId);
              return (
                <div className={removed ? "treasury-row signers editable removed" : "treasury-row signers editable"} key={signer.signerId}>
                  <div className="treasury-cell">
                    <strong>{signer.label}{signer.mine ? <span className="treasury-tag you">you</span> : null}</strong>
                    {signer.address ? <AddressChip address={signer.address} /> : <small>{signer.kind} signer {shortAddress(signer.signerId)}</small>}
                  </div>
                  <PermissionBadges permissions={signer.permissions} />
                  <button type="button" className="page-cta ghost small" onClick={() => toggleRemove(signer.signerId)} disabled={submitting}>
                    {removed ? <><RotateCcw size={13} /> Keep</> : <><Trash2 size={13} /> Remove</>}
                  </button>
                </div>
              );
            })}
          </div>
        </section>

        <section className="dash-panel">
          <div className="panel-heading">
            <div><h2>Add signers</h2><p>New ECDSA signers with their permissions</p></div>
            <div className="treasury-actions">
              <button type="button" className="page-cta ghost" onClick={() => setDraft((current) => ({ ...current, added: [...current.added, newSignerDraft()] }))} disabled={submitting}>
                <Plus size={15} /> Add signer
              </button>
            </div>
          </div>
          {draft.added.length === 0 ? <p className="treasury-muted">No new signers.</p> : null}
          <SignerRows
            rows={draft.added}
            offset={account.signers.length}
            onChange={patchAdded}
            onRemove={(key) => setDraft((current) => ({ ...current, added: current.added.filter((signer) => signer.key !== key) }))}
          />
        </section>
      </div>

      <div className="page-stack">
        <section className="dash-panel">
          <div className="panel-heading compact"><h2>Thresholds</h2></div>
          <div className="field-list">
            <label className="field-row">
              <span>Signatures needed</span>
              <input type="number" min={1} value={draft.threshold} onChange={(event) => setDraft((current) => ({ ...current, threshold: Math.max(1, Math.floor(Number(event.target.value) || 1)) }))} disabled={submitting} />
              <small className="treasury-hint">{draft.threshold} of {approversAfter} approving signers after this change. Now {account.threshold} of {account.signers.length}.</small>
            </label>
            <label className="field-row">
              <span>Veto threshold</span>
              <input type="number" min={0} value={draft.vetoThreshold} onChange={(event) => setDraft((current) => ({ ...current, vetoThreshold: Math.max(0, Math.floor(Number(event.target.value) || 0)) }))} disabled={submitting} />
              <small className="treasury-hint">0 is automatic; today {account.effectiveVetoThreshold} {account.effectiveVetoThreshold === 1 ? "veto stops" : "vetoes stop"} a scheduled change.</small>
            </label>
          </div>
        </section>

        <section className="dash-panel">
          <div className="panel-heading compact"><h2>Delays</h2></div>
          <div className="field-list">
            <DurationField label="Config delay" value={draft.configDelay} onChange={(seconds) => setDraft((current) => ({ ...current, configDelay: seconds }))} />
            <DurationField label="Recovery delay" value={draft.recoveryDelay} onChange={(seconds) => setDraft((current) => ({ ...current, recoveryDelay: seconds }))} />
            <DurationField label="Recovery co-sign delay" value={draft.recoveryCoSignDelay} onChange={(seconds) => setDraft((current) => ({ ...current, recoveryCoSignDelay: seconds }))} />
          </div>
        </section>

        <section className="dash-panel">
          <div className="treasury-note">
            <span>
              This creates a proposal. Once {account.threshold} of {account.signers.length} signers confirm it and it is executed, the change waits {durationLabel(account.configDelay)} before it takes effect, and any signer holding veto can stop it during that wait ({account.effectiveVetoThreshold} {account.effectiveVetoThreshold === 1 ? "veto ends" : "vetoes end"} it).
            </span>
          </div>
          <InlineError message={error} />
          <button type="submit" className="page-cta" disabled={submitting || !changed}>
            {submitting ? <><Loader2 size={15} className="spin" /> Creating proposal</> : "Propose change"}
          </button>
        </section>
      </div>
    </form>
  );
}

export function TreasuryRulesPage({ address }: { address: string }) {
  const account = useTreasuryAccount(address);

  if (account.isLoading) {
    return <TreasuryFrame><PanelLoading title="Loading the account" /></TreasuryFrame>;
  }
  if (account.error || !account.data) {
    return <TreasuryFrame><section className="dash-panel"><InlineError message={errorMessage(account.error)} /></section></TreasuryFrame>;
  }

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <BackLink href={`/treasury/${address}`} label={account.data.name} />
          <h1>Rules</h1>
          <p>Signers, thresholds and delays are enforced by the account on chain. Editing them produces one proposal that waits the config delay and can be vetoed.</p>
        </div>
      </header>
      <RulesEditor address={address} account={account.data} />
    </TreasuryFrame>
  );
}
