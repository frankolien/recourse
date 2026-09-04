"use client";

import { Loader2, Plus, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import {
  errorMessage,
  formatDay,
  formatUsdc,
  isValidAddress,
  nowSeconds,
  parseUsdc,
  proposeTransfer,
  type RecipientInput,
} from "@/lib/treasury";
import { BackLink, InlineError, PanelLoading, TreasuryFrame } from "./treasury-common";
import { useAddressBook, useTreasuryAccount } from "./use-treasury";

interface RecipientDraft {
  key: number;
  to: string;
  amount: string;
  label: string;
  memo: string;
}

let sequence = 0;
function newRecipient(): RecipientDraft {
  sequence += 1;
  return { key: sequence, to: "", amount: "", label: "", memo: "" };
}

const DAY = 86_400;

export function TreasuryPayPage({ address }: { address: string }) {
  const router = useRouter();
  const account = useTreasuryAccount(address);
  const book = useAddressBook(address);
  const [recipients, setRecipients] = useState<RecipientDraft[]>(() => [newRecipient()]);
  const [lane, setLane] = useState("0");
  const [validDays, setValidDays] = useState(7);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  function patch(key: number, change: Partial<RecipientDraft>) {
    setRecipients((current) => current.map((row) => (row.key === key ? { ...row, ...change } : row)));
  }

  function pick(key: number, bookAddress: string) {
    const entry = (book.data ?? []).find((item) => item.address === bookAddress);
    if (entry) patch(key, { to: entry.address, label: entry.label });
  }

  const parsed = recipients.map((row) => parseUsdc(row.amount));
  const total = parsed.reduce((sum, units) => sum + (units ? BigInt(units) : 0n), 0n);
  const balance = account.data ? BigInt(account.data.usdcBalance || "0") : null;
  const overBalance = balance != null && total > balance;
  const validUntil = nowSeconds() + validDays * DAY;

  function validate(): RecipientInput[] | string {
    if (recipients.length === 0) return "Add at least one recipient.";
    if (!/^\d+$/.test(lane)) return "The lane is a non-negative number.";
    if (validDays < 1 || validDays > 30) return "A proposal can be valid for 1 to 30 days.";
    const list: RecipientInput[] = [];
    for (const [index, row] of recipients.entries()) {
      if (!isValidAddress(row.to)) return `Recipient ${index + 1} needs a valid address.`;
      const units = parsed[index];
      if (!units) return `Recipient ${index + 1} needs an amount in USDC with at most 6 decimals.`;
      const entry: RecipientInput = { to: row.to.toLowerCase(), amount: units };
      if (row.label.trim()) entry.label = row.label.trim();
      if (row.memo.trim()) entry.memo = row.memo.trim();
      list.push(entry);
    }
    return list;
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const list = validate();
    if (typeof list === "string") {
      setError(list);
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const view = await proposeTransfer(address, { recipients: list, nonceKey: lane, validUntil: nowSeconds() + validDays * DAY });
      router.push(`/treasury/${address}/proposals/${view.txHash}`);
    } catch (cause) {
      setError(errorMessage(cause));
      setSubmitting(false);
    }
  }

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
          <h1>New payment</h1>
          <p>One proposal pays every recipient in a single transaction once {account.data.threshold} of {account.data.signers.length} signers have confirmed it.</p>
        </div>
      </header>

      <form className="two-col" onSubmit={(event) => void submit(event)}>
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Recipients</h2><p>Amounts in USDC, up to 6 decimals</p></div>
              <div className="treasury-actions">
                <button type="button" className="page-cta ghost" onClick={() => setRecipients((current) => [...current, newRecipient()])} disabled={submitting}>
                  <Plus size={15} /> Add recipient
                </button>
              </div>
            </div>
            <div className="treasury-form-rows">
              {recipients.map((row, index) => (
                <div className="treasury-form-row recipient" key={row.key}>
                  <label className="field-row">
                    <span>Address</span>
                    <input value={row.to} placeholder="0x…" spellCheck={false} onChange={(event) => patch(row.key, { to: event.target.value.trim() })} />
                  </label>
                  <label className="field-row">
                    <span>From address book</span>
                    <select value="" onChange={(event) => pick(row.key, event.target.value)} disabled={!book.data?.length}>
                      <option value="">{book.data?.length ? "Pick a saved address" : "No saved addresses"}</option>
                      {(book.data ?? []).map((entry) => (
                        <option key={entry.address} value={entry.address}>{entry.label}</option>
                      ))}
                    </select>
                  </label>
                  <label className="field-row">
                    <span>Amount (USDC)</span>
                    <input value={row.amount} inputMode="decimal" placeholder="250.00" onChange={(event) => patch(row.key, { amount: event.target.value })} />
                  </label>
                  <label className="field-row">
                    <span>Label</span>
                    <input value={row.label} placeholder="Acme Ltd" onChange={(event) => patch(row.key, { label: event.target.value })} />
                  </label>
                  <label className="field-row wide">
                    <span>Memo</span>
                    <input value={row.memo} placeholder="Invoice 1042" onChange={(event) => patch(row.key, { memo: event.target.value })} />
                  </label>
                  <button type="button" className="rule-remove" aria-label={`Remove recipient ${index + 1}`} onClick={() => setRecipients((current) => current.filter((item) => item.key !== row.key))}>
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
            </div>
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Timing</h2></div>
            <div className="builder-grid">
              <label className="field-row">
                <span>Lane</span>
                <input value={lane} inputMode="numeric" onChange={(event) => setLane(event.target.value.trim())} />
                <small className="treasury-hint">Proposals in one lane run in order; use another lane for a payment that must not wait behind this one.</small>
              </label>
              <label className="field-row">
                <span>Valid for (days)</span>
                <input type="number" min={1} max={30} value={validDays} onChange={(event) => setValidDays(Math.max(1, Math.min(30, Math.floor(Number(event.target.value) || 1))))} />
                <small className="treasury-hint">Expires on {formatDay(validUntil)} if not executed by then.</small>
              </label>
            </div>
          </section>
        </div>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Summary</h2></div>
            <dl className="treasury-kv">
              <div><dt>Total</dt><dd>{formatUsdc(total)}</dd></div>
              <div><dt>Account balance</dt><dd>{balance != null ? formatUsdc(balance) : ""}</dd></div>
              <div><dt>Needs</dt><dd>{account.data.threshold} of {account.data.signers.length} signatures</dd></div>
            </dl>
            {overBalance ? <div className="treasury-note warn">The total exceeds the balance. The proposal can still be signed, but it will not execute until the account is funded.</div> : null}
            <InlineError message={error} />
            <button type="submit" className="page-cta" disabled={submitting}>
              {submitting ? <><Loader2 size={15} className="spin" /> Creating proposal</> : "Create proposal"}
            </button>
          </section>
        </div>
      </form>
    </TreasuryFrame>
  );
}
