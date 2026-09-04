"use client";

import { useQueryClient } from "@tanstack/react-query";
import { Fingerprint, Loader2, Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { useSession } from "@/components/session-provider";
import { createAccount, durationLabel, errorMessage, isValidAddress, sameAddress, shortAddress, type CreateAccountBody } from "@/lib/treasury";
import { useArcWallet } from "@/lib/wallet";
import { BackLink, InlineError, TreasuryFrame } from "./treasury-common";
import { DurationField, SignerRows, newSignerDraft, permissionsOf, type SignerDraft } from "./treasury-forms";
import { treasuryKeys } from "./use-treasury";

const DAY = 86_400;

export function NewTreasuryAccountPage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const { account } = useSession();
  const browserAddress = useArcWallet(account?.accountId);

  const [name, setName] = useState("");
  const [signers, setSigners] = useState<SignerDraft[]>(() => [newSignerDraft()]);
  const [threshold, setThreshold] = useState(1);
  const [vetoThreshold, setVetoThreshold] = useState(0);
  const [configDelay, setConfigDelay] = useState(DAY);
  const [recoveryDelay, setRecoveryDelay] = useState(DAY);
  const [recoveryCoSignDelay, setRecoveryCoSignDelay] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [deploying, setDeploying] = useState(false);

  const usingBrowserKey = browserAddress ? signers.some((signer) => sameAddress(signer.address, browserAddress)) : false;
  const approvers = signers.filter((signer) => signer.approve).length;

  function patch(key: number, change: Partial<SignerDraft>) {
    setSigners((current) => current.map((signer) => (signer.key === key ? { ...signer, ...change } : signer)));
  }

  function remove(key: number) {
    setSigners((current) => current.filter((signer) => signer.key !== key));
  }

  function useBrowserKey() {
    if (!browserAddress || usingBrowserKey) return;
    setSigners((current) => {
      const empty = current.findIndex((signer) => !signer.address && !signer.label);
      if (empty >= 0) {
        return current.map((signer, index) => (index === empty ? { ...signer, address: browserAddress, label: "Me (browser key)" } : signer));
      }
      return [...current, newSignerDraft({ address: browserAddress, label: "Me (browser key)" })];
    });
  }

  function validate(): CreateAccountBody | string {
    if (!name.trim()) return "Give the account a name.";
    if (signers.length === 0) return "Add at least one signer.";
    const seen = new Set<string>();
    for (const [index, signer] of signers.entries()) {
      if (!isValidAddress(signer.address)) return `Signer ${index + 1} needs a valid address.`;
      const lower = signer.address.toLowerCase();
      if (seen.has(lower)) return `Signer ${index + 1} repeats an address already in the list.`;
      seen.add(lower);
      if (!signer.approve && !signer.veto) return `Signer ${index + 1} needs at least one permission.`;
    }
    if (threshold < 1 || threshold > approvers) return `The threshold must be between 1 and ${approvers}, the number of signers that can approve.`;
    if (vetoThreshold < 0) return "The veto threshold cannot be negative.";
    return {
      name: name.trim(),
      signers: signers.map((signer, index) => ({
        kind: "ecdsa",
        address: signer.address.toLowerCase(),
        label: signer.label.trim() || `Signer ${index + 1}`,
        permissions: permissionsOf(signer),
      })),
      threshold,
      vetoThreshold,
      configDelay,
      recoveryDelay,
      recoveryCoSignDelay,
    };
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const body = validate();
    if (typeof body === "string") {
      setError(body);
      return;
    }
    setError(null);
    setDeploying(true);
    try {
      const view = await createAccount(body);
      await queryClient.invalidateQueries({ queryKey: treasuryKeys.accounts });
      router.push(`/treasury/${view.address}`);
    } catch (cause) {
      setError(errorMessage(cause));
      setDeploying(false);
    }
  }

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <BackLink href="/treasury" label="Treasury" />
          <h1>New account</h1>
          <p>Name the account, list its signers and set how many of them a payment needs. It deploys on Arc testnet at once.</p>
        </div>
      </header>

      {deploying ? (
        <section className="dash-panel state-inline">
          <Loader2 size={20} className="spin" />
          <div>
            <strong>Deploying on Arc testnet</strong>
            <p>The service sends createAccount from its relayer and waits for the receipt. This usually takes 10 to 30 seconds.</p>
          </div>
        </section>
      ) : null}

      <form className="two-col" onSubmit={(event) => void submit(event)}>
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Account</h2></div>
            <label className="field-row">
              <span>Name</span>
              <input value={name} placeholder="Northwind treasury" onChange={(event) => setName(event.target.value)} disabled={deploying} />
            </label>
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Signers</h2><p>Each signer is an Ethereum address; approve lets it sign proposals, veto lets it stop scheduled rule changes</p></div>
              <div className="treasury-actions">
                <button type="button" className="page-cta ghost" onClick={() => setSigners((current) => [...current, newSignerDraft()])} disabled={deploying}>
                  <Plus size={15} /> Add signer
                </button>
              </div>
            </div>
            <SignerRows rows={signers} onChange={patch} onRemove={remove} />
            <div className="treasury-keyrow">
              <div>
                <strong><Fingerprint size={14} /> Use my browser key</strong>
                <small>{browserAddress ? `${shortAddress(browserAddress)}, the key this workspace already signs with` : "Preparing your browser key"}</small>
              </div>
              <button type="button" className="page-cta ghost" onClick={useBrowserKey} disabled={!browserAddress || usingBrowserKey || deploying}>
                {usingBrowserKey ? "Added" : "Add as signer"}
              </button>
            </div>
          </section>
        </div>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Threshold</h2></div>
            <label className="field-row">
              <span>Signatures needed</span>
              <input type="number" min={1} max={Math.max(1, approvers)} value={threshold} onChange={(event) => setThreshold(Math.max(1, Math.floor(Number(event.target.value) || 1)))} disabled={deploying} />
            </label>
            <p className="treasury-hint">{threshold} of {approvers || "the"} approving {approvers === 1 ? "signer" : "signers"} must sign before a payment or a rule change runs.</p>
          </section>

          <details className="dash-panel treasury-advanced">
            <summary>Advanced</summary>
            <div className="field-list">
              <label className="field-row">
                <span>Veto threshold</span>
                <input type="number" min={0} value={vetoThreshold} onChange={(event) => setVetoThreshold(Math.max(0, Math.floor(Number(event.target.value) || 0)))} disabled={deploying} />
                <small className="treasury-hint">0 means automatic: the account derives how many vetoes stop a scheduled change from the threshold.</small>
              </label>
              <DurationField label="Config delay" value={configDelay} onChange={setConfigDelay} hint={`Changes to signers or rules wait ${durationLabel(configDelay)} after execution and can be vetoed in that time.`} />
              <DurationField label="Recovery delay" value={recoveryDelay} onChange={setRecoveryDelay} hint="A recovery waits this long. The contract refuses less than 1 hour when a recover signer exists." />
              <DurationField label="Recovery co-sign delay" value={recoveryCoSignDelay} onChange={setRecoveryCoSignDelay} hint="Extra wait before a recovery that has a co-signature." />
            </div>
          </details>

          <section className="dash-panel">
            <InlineError message={error} />
            <button type="submit" className="page-cta" disabled={deploying}>
              {deploying ? <><Loader2 size={15} className="spin" /> Deploying</> : "Create account"}
            </button>
            <p className="treasury-hint">The address is predicted from the signers and salt; the relayer pays the deployment.</p>
          </section>
        </div>
      </form>
    </TreasuryFrame>
  );
}
