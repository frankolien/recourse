"use client";

import { useQueryClient } from "@tanstack/react-query";
import { Check, Loader2, Wallet } from "lucide-react";
import { useState } from "react";
import { useAccount, useSignMessage } from "wagmi";
import { ConnectWallet } from "@/components/connect-wallet";
import { useSession } from "@/components/session-provider";
import { errorMessage, formatDay, formatNative, linkAddress, linkMessage, sameAddress } from "@/lib/treasury";
import { useArcWallet } from "@/lib/wallet";
import { AddressChip, InlineError } from "./treasury-common";
import { treasuryKeys, useLinkedAddresses, useNativeBalance } from "./use-treasury";

function KeyRow({ address, linkedAt, tags }: { address: string; linkedAt: number | null; tags: string[] }) {
  const balance = useNativeBalance(address);
  return (
    <div className="treasury-row keys">
      <div className="treasury-cell">
        <AddressChip address={address} />
        {tags.length ? <small>{tags.join(" · ")}</small> : null}
      </div>
      <div className="treasury-cell num">
        <strong>{balance.data != null ? formatNative(balance.data) : balance.error ? "unavailable" : "…"}</strong>
        <small>native USDC, pays gas</small>
      </div>
      <div className="treasury-cell">
        <strong>{linkedAt ? formatDay(linkedAt) : "Linking"}</strong>
        <small>{linkedAt ? "linked" : "signing the link message"}</small>
      </div>
    </div>
  );
}

export function SigningKeysPanel() {
  const { account } = useSession();
  const accountId = account?.accountId;
  const browserAddress = useArcWallet(accountId);
  const linked = useLinkedAddresses();
  const queryClient = useQueryClient();
  const { address: walletAddress, isConnected } = useAccount();
  const { signMessageAsync } = useSignMessage();
  const [linking, setLinking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const entries = linked.data ?? [];
  const browserLinked = browserAddress ? entries.some((entry) => sameAddress(entry.address, browserAddress)) : false;
  const walletLinked = walletAddress ? entries.some((entry) => sameAddress(entry.address, walletAddress)) : false;

  async function linkWallet() {
    if (!walletAddress || accountId == null) return;
    setError(null);
    setLinking(true);
    try {
      const signature = await signMessageAsync({ message: linkMessage(walletAddress, accountId) });
      await linkAddress({ address: walletAddress.toLowerCase(), signature });
      await queryClient.invalidateQueries({ queryKey: treasuryKeys.linked });
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setLinking(false);
    }
  }

  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div>
          <h2>Your signing keys</h2>
          <p>Addresses you have proved you control. Any account that names one as a signer shows up above.</p>
        </div>
        <div className="treasury-actions">
          {!isConnected || !walletAddress ? (
            <ConnectWallet className="page-cta ghost" />
          ) : walletLinked ? (
            <span className="treasury-tag you"><Check size={12} /> MetaMask linked</span>
          ) : (
            <button type="button" className="page-cta ghost" disabled={linking} onClick={() => void linkWallet()}>
              {linking ? <><Loader2 size={14} className="spin" /> Sign in MetaMask</> : <><Wallet size={14} /> Link MetaMask</>}
            </button>
          )}
        </div>
      </div>
      {linked.isLoading ? (
        <div className="state-inline"><Loader2 size={18} className="spin" /><div><strong>Loading linked addresses</strong></div></div>
      ) : linked.error ? (
        <InlineError message={errorMessage(linked.error)} />
      ) : (
        <div className="treasury-rows">
          <div className="treasury-row keys head"><span>Address</span><span>Gas balance</span><span>Linked</span></div>
          {browserAddress && !browserLinked ? <KeyRow address={browserAddress} linkedAt={null} tags={["browser key"]} /> : null}
          {entries.map((entry) => (
            <KeyRow
              key={entry.address}
              address={entry.address}
              linkedAt={entry.linkedAt}
              tags={[
                ...(sameAddress(entry.address, browserAddress) ? ["browser key"] : []),
                ...(sameAddress(entry.address, walletAddress) ? ["connected wallet"] : []),
              ]}
            />
          ))}
        </div>
      )}
      <InlineError message={error} />
      <p className="treasury-hint">
        The gas balance is the address&apos;s native USDC on Arc testnet. A key needs a little of it to veto a scheduled change from the browser; confirming and executing cost it nothing, the relayer pays.
      </p>
    </section>
  );
}
