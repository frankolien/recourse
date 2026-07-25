"use client";

import { Check, Wallet } from "lucide-react";
import { useState } from "react";
import { shortAddr } from "@/lib/api";
import { useArcWallet } from "@/lib/wallet";

// The account's provisioned Arc wallet, always present after sign-in; replaces the
// old "Connect wallet" ask so the workspace works without any browser extension.
export function ArcWalletBadge({ accountId }: { accountId: number }) {
  const address = useArcWallet(accountId);
  const [copied, setCopied] = useState(false);

  if (!address) return null;
  return (
    <button
      className="wallet-badge"
      type="button"
      title={`${address} (click to copy)`}
      onClick={() => {
        navigator.clipboard.writeText(address);
        setCopied(true);
        setTimeout(() => setCopied(false), 1600);
      }}
    >
      {copied ? <Check size={15} /> : <Wallet size={15} />}
      {copied ? "Copied" : shortAddr(address)}
    </button>
  );
}
