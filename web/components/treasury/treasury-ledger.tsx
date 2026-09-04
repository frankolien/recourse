"use client";

import { useQueryClient } from "@tanstack/react-query";
import { ArrowDownLeft, ArrowUpRight, Loader2, Plus } from "lucide-react";
import { useState, type FormEvent } from "react";
import { addAddressBookEntry, errorMessage, formatTime, formatUsdc, isValidAddress } from "@/lib/treasury";
import { AddressChip, BackLink, InlineError, PanelLoading, TreasuryFrame, TxChip } from "./treasury-common";
import { treasuryKeys, useAddressBook, useLedger, useTreasuryAccount } from "./use-treasury";

function AddressBookPanel({ address }: { address: string }) {
  const book = useAddressBook(address);
  const queryClient = useQueryClient();
  const [entryAddress, setEntryAddress] = useState("");
  const [label, setLabel] = useState("");
  const [category, setCategory] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!isValidAddress(entryAddress)) {
      setError("Enter a valid address.");
      return;
    }
    if (!label.trim()) {
      setError("Give the address a label.");
      return;
    }
    setError(null);
    setSaving(true);
    try {
      await addAddressBookEntry(address, {
        address: entryAddress.toLowerCase(),
        label: label.trim(),
        ...(category.trim() ? { category: category.trim() } : {}),
      });
      await queryClient.invalidateQueries({ queryKey: treasuryKeys.addressBook(address) });
      setEntryAddress("");
      setLabel("");
      setCategory("");
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setSaving(false);
    }
  }

  const entries = book.data ?? [];

  return (
    <section className="dash-panel" id="address-book">
      <div className="panel-heading">
        <div><h2>Address book</h2><p>Labels for counterparties; they show in the ledger and in the payment form</p></div>
      </div>
      {book.isLoading ? (
        <div className="state-inline"><Loader2 size={18} className="spin" /><div><strong>Loading the address book</strong></div></div>
      ) : book.error ? (
        <InlineError message={errorMessage(book.error)} />
      ) : entries.length === 0 ? (
        <p className="treasury-muted">No saved addresses yet.</p>
      ) : (
        <div className="treasury-rows">
          <div className="treasury-row book head"><span>Label</span><span>Address</span><span>Category</span></div>
          {entries.map((entry) => (
            <div className="treasury-row book" key={entry.address}>
              <div className="treasury-cell"><strong>{entry.label}</strong></div>
              <AddressChip address={entry.address} />
              <div className="treasury-cell"><small>{entry.category ?? ""}</small></div>
            </div>
          ))}
        </div>
      )}
      <form className="treasury-form-row book-add" onSubmit={(event) => void submit(event)}>
        <label className="field-row">
          <span>Address</span>
          <input value={entryAddress} placeholder="0x…" spellCheck={false} onChange={(event) => setEntryAddress(event.target.value.trim())} />
        </label>
        <label className="field-row">
          <span>Label</span>
          <input value={label} placeholder="Acme Ltd" onChange={(event) => setLabel(event.target.value)} />
        </label>
        <label className="field-row">
          <span>Category (optional)</span>
          <input value={category} placeholder="supplier" onChange={(event) => setCategory(event.target.value)} />
        </label>
        <button type="submit" className="page-cta ghost" disabled={saving}>
          {saving ? <><Loader2 size={14} className="spin" /> Saving</> : <><Plus size={14} /> Add</>}
        </button>
      </form>
      <InlineError message={error} />
    </section>
  );
}

export function TreasuryLedgerPage({ address }: { address: string }) {
  const account = useTreasuryAccount(address);
  const ledger = useLedger(address);

  if (account.isLoading) {
    return <TreasuryFrame><PanelLoading title="Loading the ledger" /></TreasuryFrame>;
  }
  if (account.error || !account.data) {
    return <TreasuryFrame><section className="dash-panel"><InlineError message={errorMessage(account.error)} /></section></TreasuryFrame>;
  }

  const entries = ledger.data ?? [];

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <BackLink href={`/treasury/${address}`} label={account.data.name} />
          <h1>Ledger</h1>
          <p>Every USDC transfer where the account or one of its sub-accounts is a party, with the proposal and memo behind it.</p>
        </div>
      </header>

      <section className="dash-panel">
        <div className="panel-heading">
          <div><h2>Movements</h2><p>Newest first, from USDC Transfer logs</p></div>
        </div>
        {ledger.isLoading ? (
          <div className="state-inline"><Loader2 size={18} className="spin" /><div><strong>Loading movements</strong></div></div>
        ) : ledger.error ? (
          <InlineError message={errorMessage(ledger.error)} />
        ) : entries.length === 0 ? (
          <p className="treasury-muted">No movements yet. Send USDC to the account address to fund it.</p>
        ) : (
          <div className="treasury-rows">
            <div className="treasury-row ledger head">
              <span /><span>Counterparty</span><span>Amount</span><span>Time</span><span>Transaction</span><span>Memo</span>
            </div>
            {entries.map((entry) => (
              <div className="treasury-row ledger" key={`${entry.tx}-${entry.logIndex}`}>
                <span className={entry.direction === "in" ? "treasury-direction in" : "treasury-direction out"} title={entry.direction === "in" ? "Received" : "Sent"}>
                  {entry.direction === "in" ? <ArrowDownLeft size={14} /> : <ArrowUpRight size={14} />}
                </span>
                <div className="treasury-cell">
                  {entry.counterpartyLabel ? <strong>{entry.counterpartyLabel}</strong> : null}
                  <AddressChip address={entry.counterparty} />
                </div>
                <div className="treasury-cell num">
                  <strong>{entry.direction === "in" ? "+" : "-"}{formatUsdc(entry.amount)}</strong>
                  {entry.symbol && entry.symbol !== "USDC" ? <small>{entry.symbol}</small> : null}
                </div>
                <div className="treasury-cell"><strong>{formatTime(entry.blockTime)}</strong><small>block {entry.blockNumber}</small></div>
                <TxChip hash={entry.tx} />
                <div className="treasury-cell"><small>{entry.memo ?? ""}</small></div>
              </div>
            ))}
          </div>
        )}
      </section>

      <AddressBookPanel address={address} />
    </TreasuryFrame>
  );
}
