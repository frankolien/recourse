"use client";

import { Check, Fingerprint, Loader2, Wallet } from "lucide-react";
import { useState } from "react";
import { useAccount, useSignTypedData, useSwitchChain } from "wagmi";
import { ConnectWallet } from "@/components/connect-wallet";
import { useSession } from "@/components/session-provider";
import { arcTestnet } from "@/lib/contracts";
import {
  confirmProposal,
  errorMessage,
  proposalHash,
  sameAddress,
  shortAddress,
  signerIdFor,
  typedDataFor,
  type AccountView,
  type ProposalStatus,
  type ProposalView,
} from "@/lib/treasury";
import { useArcWallet, walletFor } from "@/lib/wallet";
import { InlineError } from "./treasury-common";

const SIGNABLE: ProposalStatus[] = ["open", "ready", "blocked"];

function ecdsaSigner(account: AccountView, address: string | null | undefined) {
  if (!address) return null;
  return account.signers.find((signer) => signer.kind === "ecdsa" && sameAddress(signer.address, address)) ?? null;
}

function alreadyConfirmed(proposal: ProposalView, address: string) {
  const id = signerIdFor(address);
  return proposal.confirmations.some((confirmation) => confirmation.signerId.toLowerCase() === id);
}

// The two ways a member signs from a browser: the account's own browser key, or an
// injected wallet. Both sign the same typed data and post the same confirmation,
// and neither is asked to sign until the typed data hashes to the proposal's txHash.
export function ConfirmControls({
  account,
  proposal,
  onUpdated,
}: {
  account: AccountView;
  proposal: ProposalView;
  onUpdated: (view: ProposalView) => void;
}) {
  const { account: session } = useSession();
  const accountId = session?.accountId;
  const browserAddress = useArcWallet(accountId);
  const { address: walletAddress, isConnected, chainId } = useAccount();
  const { signTypedDataAsync } = useSignTypedData();
  const { switchChainAsync } = useSwitchChain();
  const [busy, setBusy] = useState<"browser" | "wallet" | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!SIGNABLE.includes(proposal.status)) return null;

  const browserSigner = ecdsaSigner(account, browserAddress);
  const walletSigner = ecdsaSigner(account, walletAddress);
  const browserDone = browserAddress ? alreadyConfirmed(proposal, browserAddress) : false;
  const walletDone = walletAddress ? alreadyConfirmed(proposal, walletAddress) : false;

  function hashChecksOut(): boolean {
    const hash = proposalHash(proposal);
    if (hash.toLowerCase() !== proposal.txHash.toLowerCase()) {
      setError(`Hash mismatch, not signing. The typed data hashes to ${hash}, the proposal says ${proposal.txHash}.`);
      return false;
    }
    return true;
  }

  async function submit(address: string, signature: string) {
    const view = await confirmProposal(account.address, proposal.txHash, { signerId: signerIdFor(address), signature });
    onUpdated(view);
  }

  async function signWithBrowserKey() {
    if (accountId == null || !browserAddress || !browserSigner) return;
    setError(null);
    setBusy("browser");
    try {
      if (!hashChecksOut()) return;
      const signature = await walletFor(accountId).signTypedData(typedDataFor(proposal));
      await submit(browserAddress, signature);
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(null);
    }
  }

  async function signWithWallet() {
    if (!walletAddress || !walletSigner) return;
    setError(null);
    setBusy("wallet");
    try {
      if (chainId !== arcTestnet.id) await switchChainAsync({ chainId: arcTestnet.id });
      if (!hashChecksOut()) return;
      const data = typedDataFor(proposal);
      const signature = await signTypedDataAsync({
        domain: data.domain,
        types: data.types,
        primaryType: data.primaryType,
        message: data.message,
      });
      await submit(walletAddress, signature);
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div>
          <h2>Sign</h2>
          <p>The console hashes the typed data itself and refuses to sign when it differs from the proposal hash</p>
        </div>
      </div>
      <div className="treasury-sign-grid">
        <div className="treasury-sign-option">
          <strong><Fingerprint size={15} /> Browser key</strong>
          {browserAddress ? <small>{shortAddress(browserAddress)}</small> : null}
          {!browserSigner ? (
            <p className="treasury-muted">Your browser key is not a signer of this account.</p>
          ) : browserDone ? (
            <p className="treasury-ok"><Check size={14} /> Confirmed with this key.</p>
          ) : (
            <button type="button" className="page-cta" disabled={busy !== null} onClick={() => void signWithBrowserKey()}>
              {busy === "browser" ? <><Loader2 size={15} className="spin" /> Signing</> : "Confirm with browser key"}
            </button>
          )}
        </div>
        <div className="treasury-sign-option">
          <strong><Wallet size={15} /> MetaMask</strong>
          {!isConnected || !walletAddress ? (
            <>
              <p className="treasury-muted">Connect a wallet whose address is one of the signers.</p>
              <ConnectWallet className="page-cta ghost" />
            </>
          ) : !walletSigner ? (
            <p className="treasury-muted">{shortAddress(walletAddress)} is not a signer of this account.</p>
          ) : walletDone ? (
            <p className="treasury-ok"><Check size={14} /> Confirmed with {shortAddress(walletAddress)}.</p>
          ) : (
            <>
              <small>{shortAddress(walletAddress)}{chainId !== arcTestnet.id ? ", will switch to Arc testnet first" : ""}</small>
              <button type="button" className="page-cta" disabled={busy !== null} onClick={() => void signWithWallet()}>
                {busy === "wallet" ? <><Loader2 size={15} className="spin" /> Confirm in wallet</> : "Confirm with MetaMask"}
              </button>
            </>
          )}
        </div>
      </div>
      <InlineError message={error} />
    </section>
  );
}
