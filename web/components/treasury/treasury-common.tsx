"use client";

import { ArrowLeft, ArrowUpRight, Check, Copy, Loader2, TriangleAlert } from "lucide-react";
import Link from "next/link";
import { useState, type ReactNode } from "react";
import { explorerAddressUrl, explorerTxUrl } from "@/lib/contracts";
import {
  countdownLabel,
  shortAddress,
  shortHash,
  statusLabel,
  statusTone,
  type Permission,
  type ProposalStatus,
} from "@/lib/treasury";
import { useBrowserKeyLink, useNow } from "./use-treasury";

export function CopyButton({ value, title = "Copy" }: { value: string; title?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className="treasury-icon-button"
      title={copied ? "Copied" : title}
      aria-label={copied ? "Copied" : title}
      onClick={() => {
        void navigator.clipboard.writeText(value);
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1400);
      }}
    >
      {copied ? <Check size={13} /> : <Copy size={13} />}
    </button>
  );
}

// Every address in the console reads the same way: short form, copy, explorer.
export function AddressChip({ address, label }: { address: string; label?: string | null }) {
  return (
    <span className="treasury-chip">
      {label ? <strong>{label}</strong> : null}
      <code title={address}>{shortAddress(address)}</code>
      <CopyButton value={address} title="Copy address" />
      <a href={explorerAddressUrl(address)} target="_blank" rel="noreferrer" title="Open in ArcScan" aria-label="Open in ArcScan">
        <ArrowUpRight size={13} />
      </a>
    </span>
  );
}

export function TxChip({ hash }: { hash: string }) {
  return (
    <span className="treasury-chip">
      <code title={hash}>{shortHash(hash)}</code>
      <CopyButton value={hash} title="Copy transaction hash" />
      <a href={explorerTxUrl(hash)} target="_blank" rel="noreferrer" title="Open in ArcScan" aria-label="Open in ArcScan">
        <ArrowUpRight size={13} />
      </a>
    </span>
  );
}

export function StatusPill({ status }: { status: ProposalStatus }) {
  return <span className={`status-pill ${statusTone(status)}`}>{statusLabel(status)}</span>;
}

export function InlineError({ message }: { message: string | null | undefined }) {
  if (!message) return null;
  return (
    <p className="treasury-error" role="alert">
      <TriangleAlert size={14} /> {message}
    </p>
  );
}

export function PanelLoading({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="dash-panel state-inline">
      <Loader2 size={18} className="spin" />
      <div>
        <strong>{title}</strong>
        {hint ? <p>{hint}</p> : null}
      </div>
    </div>
  );
}

export function PermissionBadges({ permissions }: { permissions: Permission[] }) {
  return (
    <span className="treasury-tags">
      {permissions.map((permission) => (
        <span className="treasury-tag" key={permission}>{permission}</span>
      ))}
    </span>
  );
}

export function Countdown({ target }: { target: number }) {
  const now = useNow();
  const label = countdownLabel(target, now);
  return <span className={label === "ready" ? "treasury-countdown ready" : "treasury-countdown"}>{label}</span>;
}

export function KeyValue({ items }: { items: { label: string; value: ReactNode }[] }) {
  return (
    <dl className="treasury-kv">
      {items.map((item) => (
        <div key={item.label}>
          <dt>{item.label}</dt>
          <dd>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

export function BackLink({ href, label }: { href: string; label: string }) {
  return (
    <Link href={href} className="back-link">
      <ArrowLeft size={15} /> {label}
    </Link>
  );
}

// Wraps every treasury page: links the browser key on first load so accounts that
// name it as a signer are visible, and surfaces a failed link without blocking.
export function TreasuryFrame({ children }: { children: ReactNode }) {
  const link = useBrowserKeyLink();
  return (
    <div className="page-stack">
      {link.state === "error" ? <InlineError message={`Could not link your browser key: ${link.error}`} /> : null}
      {children}
    </div>
  );
}
