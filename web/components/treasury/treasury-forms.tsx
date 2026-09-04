"use client";

import { Trash2 } from "lucide-react";
import { useState } from "react";
import type { Permission } from "@/lib/treasury";

export interface SignerDraft {
  key: number;
  label: string;
  address: string;
  approve: boolean;
  veto: boolean;
}

let draftSequence = 0;

export function newSignerDraft(partial: Partial<SignerDraft> = {}): SignerDraft {
  draftSequence += 1;
  return { key: draftSequence, label: "", address: "", approve: true, veto: true, ...partial };
}

export function permissionsOf(draft: SignerDraft): Permission[] {
  const list: Permission[] = [];
  if (draft.approve) list.push("approve");
  if (draft.veto) list.push("veto");
  return list;
}

export function SignerRows({
  rows,
  onChange,
  onRemove,
  offset = 0,
}: {
  rows: SignerDraft[];
  onChange: (key: number, patch: Partial<SignerDraft>) => void;
  onRemove: (key: number) => void;
  offset?: number;
}) {
  return (
    <div className="treasury-form-rows">
      {rows.map((row, index) => {
        const ordinal = offset + index + 1;
        return (
          <div className="treasury-form-row signer" key={row.key}>
            <label className="field-row">
              <span>Label</span>
              <input value={row.label} placeholder={`Signer ${ordinal}`} onChange={(event) => onChange(row.key, { label: event.target.value })} />
            </label>
            <label className="field-row">
              <span>Address</span>
              <input value={row.address} placeholder="0x…" spellCheck={false} onChange={(event) => onChange(row.key, { address: event.target.value.trim() })} />
            </label>
            <div className="field-row">
              <span>Permissions</span>
              <div className="treasury-checks">
                <label className="treasury-check">
                  <input type="checkbox" checked={row.approve} onChange={(event) => onChange(row.key, { approve: event.target.checked })} /> approve
                </label>
                <label className="treasury-check">
                  <input type="checkbox" checked={row.veto} onChange={(event) => onChange(row.key, { veto: event.target.checked })} /> veto
                </label>
              </div>
            </div>
            <button type="button" className="rule-remove" aria-label={`Remove signer ${ordinal}`} onClick={() => onRemove(row.key)}>
              <Trash2 size={14} />
            </button>
          </div>
        );
      })}
    </div>
  );
}

// A delay typed in hours or days and held in seconds, which is what the contract
// takes and what the request body sends.
export function DurationField({
  label,
  value,
  onChange,
  hint,
}: {
  label: string;
  value: number;
  onChange: (seconds: number) => void;
  hint?: string;
}) {
  const [unit, setUnit] = useState<"hours" | "days">(value > 0 && value % 86_400 === 0 ? "days" : "hours");
  const factor = unit === "days" ? 86_400 : 3_600;
  const shown = Math.round((value / factor) * 1000) / 1000;
  return (
    <div className="field-row">
      <span>{label}</span>
      <div className="treasury-duration">
        <input
          type="number"
          min={0}
          step="any"
          value={String(shown)}
          onChange={(event) => {
            const n = Number(event.target.value);
            onChange(Number.isFinite(n) && n >= 0 ? Math.round(n * factor) : 0);
          }}
        />
        <select value={unit} onChange={(event) => setUnit(event.target.value === "days" ? "days" : "hours")}>
          <option value="hours">hours</option>
          <option value="days">days</option>
        </select>
      </div>
      {hint ? <small className="treasury-hint">{hint}</small> : null}
    </div>
  );
}
