"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Ban, Fingerprint, Loader2, Lock, Play, Wallet } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { createWalletClient, http } from "viem";
import { useAccount, useSendTransaction, useSwitchChain } from "wagmi";
import { ConnectWallet } from "@/components/connect-wallet";
import { useSession } from "@/components/session-provider";
import { arcTestnet, publicClient } from "@/lib/contracts";
import {
  errorMessage,
  executeScheduled,
  formatTime,
  getProposal,
  getVetoCall,
  kindLabel,
  proposalSummary,
  shortAddress,
  signerIdFor,
  type Hex,
  type ProposalView,
} from "@/lib/treasury";
import { useArcWallet, walletFor } from "@/lib/wallet";
import { AddressChip, BackLink, Countdown, InlineError, PanelLoading, StatusPill, TreasuryFrame, TxChip } from "./treasury-common";
import { POLL_MS, treasuryKeys, useNow, useScheduled, useTreasuryAccount } from "./use-treasury";

const NO_GAS = "This key needs a little USDC on Arc testnet for gas before it can veto.";

function VetoControls({ address, item }: { address: string; item: ProposalView }) {
  const { account: session } = useSession();
  const accountId = session?.accountId;
  const browserAddress = useArcWallet(accountId);
  const { address: walletAddress, isConnected, chainId } = useAccount();
  const { sendTransactionAsync } = useSendTransaction();
  const { switchChainAsync } = useSwitchChain();
  const queryClient = useQueryClient();
  const vetoCall = useQuery({
    queryKey: treasuryKeys.vetoCall(address, item.txHash),
    queryFn: () => getVetoCall(address, item.txHash),
    refetchInterval: POLL_MS,
  });
  const [busy, setBusy] = useState<"browser" | "wallet" | "waiting" | null>(null);
  const [sent, setSent] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const ids = (vetoCall.data?.signerIds ?? []).map((id) => id.toLowerCase());
  const browserCan = browserAddress ? ids.includes(signerIdFor(browserAddress)) : false;
  const walletCan = walletAddress ? ids.includes(signerIdFor(walletAddress)) : false;

  // The indexer turns the Vetoed event into status "vetoed" within one interval;
  // give it a minute before handing back to the page's own polling.
  async function waitForVeto() {
    setBusy("waiting");
    const deadline = Date.now() + 60_000;
    while (Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 4_000));
      const view = await getProposal(address, item.txHash);
      if (view.status === "vetoed" || view.vetoes.length > item.vetoes.length) break;
    }
    await queryClient.invalidateQueries({ queryKey: treasuryKeys.scheduled(address) });
    await queryClient.invalidateQueries({ queryKey: treasuryKeys.vetoCall(address, item.txHash) });
  }

  async function vetoWithBrowserKey() {
    if (accountId == null || !browserAddress || !vetoCall.data) return;
    setError(null);
    setBusy("browser");
    try {
      const balance = await publicClient.getBalance({ address: browserAddress });
      if (balance === 0n) {
        setError(NO_GAS);
        return;
      }
      const wallet = createWalletClient({ account: walletFor(accountId), chain: arcTestnet, transport: http() });
      const hash = await wallet.sendTransaction({ to: vetoCall.data.to as Hex, data: vetoCall.data.data as Hex });
      setSent(hash);
      await waitForVeto();
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(null);
    }
  }

  async function vetoWithWallet() {
    if (!walletAddress || !vetoCall.data) return;
    setError(null);
    setBusy("wallet");
    try {
      if (chainId !== arcTestnet.id) await switchChainAsync({ chainId: arcTestnet.id });
      const balance = await publicClient.getBalance({ address: walletAddress });
      if (balance === 0n) {
        setError(NO_GAS);
        return;
      }
      const hash = await sendTransactionAsync({ to: vetoCall.data.to as Hex, data: vetoCall.data.data as Hex, chainId: arcTestnet.id });
      setSent(hash);
      await waitForVeto();
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(null);
    }
  }

  if (vetoCall.isLoading) return <p className="treasury-muted"><Loader2 size={14} className="spin" /> Checking whether you can veto.</p>;
  if (vetoCall.error) return <InlineError message={errorMessage(vetoCall.error)} />;

  return (
    <div className="treasury-veto">
      {busy === "waiting" ? (
        <p className="treasury-muted"><Loader2 size={14} className="spin" /> Veto sent{sent ? <>, <TxChip hash={sent} /></> : null}. Waiting for the indexer to see it.</p>
      ) : sent ? (
        <p className="treasury-ok">Veto transaction sent: <TxChip hash={sent} /></p>
      ) : null}
      <div className="treasury-sign-grid">
        <div className="treasury-sign-option">
          <strong><Fingerprint size={15} /> Browser key</strong>
          {browserAddress ? <small>{shortAddress(browserAddress)}</small> : null}
          {browserCan ? (
            <button type="button" className="page-cta" disabled={busy !== null} onClick={() => void vetoWithBrowserKey()}>
              {busy === "browser" ? <><Loader2 size={15} className="spin" /> Sending</> : <><Ban size={15} /> Veto with browser key</>}
            </button>
          ) : (
            <p className="treasury-muted">This key cannot veto this change: it is not a signer with veto, it is the signer being removed, or it already vetoed.</p>
          )}
        </div>
        <div className="treasury-sign-option">
          <strong><Wallet size={15} /> MetaMask</strong>
          {!isConnected || !walletAddress ? (
            <ConnectWallet className="page-cta ghost" />
          ) : walletCan ? (
            <>
              <small>{shortAddress(walletAddress)}</small>
              <button type="button" className="page-cta" disabled={busy !== null} onClick={() => void vetoWithWallet()}>
                {busy === "wallet" ? <><Loader2 size={15} className="spin" /> Confirm in wallet</> : <><Ban size={15} /> Veto with MetaMask</>}
              </button>
            </>
          ) : (
            <p className="treasury-muted">{shortAddress(walletAddress)} cannot veto this change.</p>
          )}
        </div>
      </div>
      <p className="treasury-hint">A veto is a transaction from the signer&apos;s own key, paid in native USDC; the relayer is not involved.</p>
      <InlineError message={error} />
    </div>
  );
}

function ScheduledCard({ address, item }: { address: string; item: ProposalView }) {
  const now = useNow();
  const queryClient = useQueryClient();
  const [executing, setExecuting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ready = item.scheduledReadyAt != null && item.scheduledReadyAt <= now;
  const windowOpen = item.scheduledWindowEndsAt == null || item.scheduledWindowEndsAt > now;

  async function runNow() {
    setError(null);
    setExecuting(true);
    try {
      await executeScheduled(address, item.txHash);
      await queryClient.invalidateQueries({ queryKey: treasuryKeys.scheduled(address) });
      await queryClient.invalidateQueries({ queryKey: treasuryKeys.account(address) });
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setExecuting(false);
    }
  }

  return (
    <section className="dash-panel">
      <div className="panel-heading">
        <div>
          <h2>{kindLabel(item.kind)}</h2>
          <p>Executed {formatTime(item.executedAt)} · <Link href={`/treasury/${address}/proposals/${item.txHash}`}>open the proposal</Link></p>
        </div>
        <div className="treasury-actions"><StatusPill status={item.status} /></div>
      </div>

      <div className="treasury-calls">
        {item.decoded.map((call, index) => (
          <div className="treasury-call" key={`${call.to}-${index}`}>
            <span className="rule-number">{index + 1}</span>
            <div>
              <strong>{call.summary}</strong>
              <small><AddressChip address={call.to} label={call.label} /> selector {call.selector}</small>
            </div>
          </div>
        ))}
        {item.decoded.length === 0 ? <p className="treasury-muted">{proposalSummary(item)}</p> : null}
      </div>

      <div className="metric-grid cols-3 treasury-stats">
        <article className="metric-card">
          <span><Lock size={12} /> Takes effect</span>
          <strong>{item.scheduledReadyAt ? <Countdown target={item.scheduledReadyAt} /> : "pending"}</strong>
          <small>{formatTime(item.scheduledReadyAt)}</small>
        </article>
        <article className="metric-card">
          <span>Window ends</span>
          <strong>{item.scheduledWindowEndsAt ? formatTime(item.scheduledWindowEndsAt) : "open"}</strong>
          <small>must run before this</small>
        </article>
        <article className="metric-card">
          <span>Vetoes</span>
          <strong>{item.vetoes.length} of {item.effectiveVetoThreshold}</strong>
          <small>{item.effectiveVetoThreshold} {item.effectiveVetoThreshold === 1 ? "stops" : "stop"} it</small>
        </article>
      </div>

      {item.vetoes.length > 0 ? (
        <div className="treasury-rows">
          {item.vetoes.map((veto) => (
            <div className="treasury-row vetoes" key={veto.signerId}>
              <span className="treasury-direction out"><Ban size={14} /></span>
              <div className="treasury-cell"><strong>{veto.label}</strong><small>{formatTime(veto.at)}</small></div>
              <TxChip hash={veto.tx} />
            </div>
          ))}
        </div>
      ) : null}

      {item.status === "scheduled" ? <VetoControls address={address} item={item} /> : null}

      {item.status === "scheduled" && ready && windowOpen ? (
        <div className="treasury-actions">
          <button type="button" className="page-cta ghost" disabled={executing} onClick={() => void runNow()}>
            {executing ? <><Loader2 size={15} className="spin" /> Executing</> : <><Play size={15} /> Apply now</>}
          </button>
          <InlineError message={error} />
        </div>
      ) : null}
    </section>
  );
}

export function TreasuryScheduledPage({ address }: { address: string }) {
  const account = useTreasuryAccount(address);
  const scheduled = useScheduled(address);

  if (account.isLoading || scheduled.isLoading) {
    return <TreasuryFrame><PanelLoading title="Loading scheduled changes" /></TreasuryFrame>;
  }
  if (account.error || !account.data || scheduled.error) {
    return <TreasuryFrame><section className="dash-panel"><InlineError message={errorMessage(scheduled.error ?? account.error)} /></section></TreasuryFrame>;
  }

  const items = scheduled.data ?? [];

  return (
    <TreasuryFrame>
      <header className="dash-header">
        <div>
          <BackLink href={`/treasury/${address}`} label={account.data.name} />
          <h1>Scheduled changes</h1>
          <p>Configuration changes the account has accepted and is waiting out. A signer with veto can stop one until it takes effect.</p>
        </div>
      </header>
      {items.length === 0 ? (
        <section className="dash-panel treasury-empty">
          <Lock size={22} />
          <div><strong>Nothing scheduled</strong><p>When a signer or rule change is executed it appears here for its delay.</p></div>
        </section>
      ) : (
        items.map((item) => <ScheduledCard address={address} item={item} key={item.txHash} />)
      )}
    </TreasuryFrame>
  );
}
