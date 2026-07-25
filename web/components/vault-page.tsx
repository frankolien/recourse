"use client";

import {
  ArrowUpRight,
  Banknote,
  Check,
  Info,
  Landmark,
  Loader2,
  Percent,
  Send,
  Wallet,
  X,
  Zap,
} from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { formatDate, formatUsdc, getPayments, getPolicies, shortAddr, type ApiPayment, type ApiPolicy } from "@/lib/api";
import {
  explorerAddressUrl,
  explorerTxUrl,
  publicClient,
  usdcAddress,
  vaultAbi,
  vaultAddress,
  yieldAdapterAddress,
} from "@/lib/contracts";
import { erc20Abi } from "viem";
import { useArcWallet, useUsdcBalance, vaultDeposit, vaultWithdraw } from "@/lib/wallet";
import { useLive } from "@/lib/use-live";
import { useSession } from "@/components/session-provider";

const contracts = [
  { label: "Settlement vault", address: vaultAddress },
  { label: "USYC yield adapter", address: yieldAdapterAddress },
  { label: "USDC (Circle)", address: usdcAddress },
];

interface VaultState {
  totalAssets: bigint;
  totalShares: bigint;
  outstanding: bigint;
  idle: bigint;
  myShares: bigint;
  myValue: bigint;
}

interface AdvanceRow {
  paymentId: number;
  merchant: string;
  amount: bigint;
  reconciled: boolean;
  releasableAt: number | null;
}

function useVaultState(lp: `0x${string}` | null, refreshKey: number): VaultState | null {
  const [state, setState] = useState<VaultState | null>(null);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const [totalAssets, totalShares, outstanding, idle, myShares] = await Promise.all([
          publicClient.readContract({ address: vaultAddress, abi: vaultAbi, functionName: "totalAssets" }),
          publicClient.readContract({ address: vaultAddress, abi: vaultAbi, functionName: "totalShares" }),
          publicClient.readContract({ address: vaultAddress, abi: vaultAbi, functionName: "outstanding" }),
          publicClient.readContract({ address: usdcAddress, abi: erc20Abi, functionName: "balanceOf", args: [vaultAddress] }),
          lp
            ? publicClient.readContract({ address: vaultAddress, abi: vaultAbi, functionName: "sharesOf", args: [lp] })
            : Promise.resolve(0n),
        ]);
        const myValue = myShares > 0n
          ? await publicClient.readContract({ address: vaultAddress, abi: vaultAbi, functionName: "convertToAssets", args: [myShares] })
          : 0n;
        if (alive) setState({ totalAssets, totalShares, outstanding, idle, myShares, myValue });
      } catch {
        // Leave the previous reading in place; the interval will retry.
      }
    };
    load();
    const timer = setInterval(load, 15_000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [lp, refreshKey]);
  return state;
}

// The vault books advances per paymentId; the indexer's payment list bounds the scan.
function useAdvances(payments: ApiPayment[] | null, policies: ApiPolicy[] | null): AdvanceRow[] | null {
  const [rows, setRows] = useState<AdvanceRow[] | null>(null);
  useEffect(() => {
    if (!payments) return;
    let alive = true;
    Promise.all(
      payments.map((p) =>
        publicClient
          .readContract({ address: vaultAddress, abi: vaultAbi, functionName: "advances", args: [BigInt(p.paymentId)] })
          .then(([merchant, amount, exists, reconciled]) => (exists ? { p, merchant, amount, reconciled } : null))
          .catch(() => null),
      ),
    ).then((results) => {
      if (!alive) return;
      const next: AdvanceRow[] = [];
      for (const r of results) {
        if (!r) continue;
        const policy = policies?.find((x) => x.policyId === r.p.policyId);
        next.push({
          paymentId: r.p.paymentId,
          merchant: r.merchant,
          amount: r.amount,
          reconciled: r.reconciled,
          releasableAt: policy ? r.p.paidAt + policy.disputeWindow : null,
        });
      }
      setRows(next.sort((a, b) => b.paymentId - a.paymentId));
    });
    return () => {
      alive = false;
    };
  }, [payments, policies]);
  return rows;
}

export function VaultPage() {
  const { account } = useSession();
  const wallet = useArcWallet(account?.accountId);
  const walletBalance = useUsdcBalance(wallet);
  const [refreshKey, setRefreshKey] = useState(0);
  const vault = useVaultState(wallet, refreshKey);
  const paymentsLive = useLive(getPayments);
  const policiesLive = useLive(getPolicies);
  const advances = useAdvances(paymentsLive.data, policiesLive.data);
  const [dialog, setDialog] = useState<"none" | "deposit" | "withdraw">("none");

  const escrowTvl = useMemo(
    () => (paymentsLive.data ?? []).filter((p) => p.status === 1 || p.status === 2).reduce((sum, p) => sum + BigInt(p.amount), 0n),
    [paymentsLive.data],
  );
  const sharePrice = vault && vault.totalShares > 0n
    ? Number(vault.totalAssets) / Number(vault.totalShares)
    : 1;

  const metrics = [
    { label: "Vault TVL", value: vault ? `$${formatUsdc(vault.totalAssets.toString()).replace(" USDC", "")}` : "…", sub: vault ? `${formatUsdc(vault.idle.toString())} idle` : "reading Arc", icon: <Landmark size={13} /> },
    { label: "LP share price", value: vault ? sharePrice.toFixed(6) : "…", sub: "Started at 1.000000", icon: <Percent size={13} /> },
    { label: "Outstanding advances", value: vault ? `$${formatUsdc(vault.outstanding.toString()).replace(" USDC", "")}` : "…", sub: `${(advances ?? []).filter((a) => !a.reconciled).length} open claims`, icon: <Zap size={13} /> },
    { label: "Escrow TVL", value: `$${formatUsdc(escrowTvl.toString()).replace(" USDC", "")}`, sub: "Earning USYC yield", icon: <Banknote size={13} /> },
  ];

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Vault and yield</h1>
          <p>LPs front merchants at T plus 0 and earn advance fees plus USYC float yield, bounded by immutable refund policies.</p>
        </div>
      </header>

      <section className="metric-grid">
        {metrics.map((metric) => (
          <article className="metric-card" key={metric.label}>
            <span>{metric.icon} {metric.label}</span>
            <strong>{metric.value}</strong>
            <small>{metric.sub}</small>
          </article>
        ))}
      </section>

      <div className="two-col">
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Advanced claims</h2><p>Merchants paid at T plus 0; the vault holds each escrow claim to settlement</p></div>
              <Link href="/payments">View payments</Link>
            </div>
            {!advances ? (
              <p className="panel-note"><Loader2 className="spin" size={14} /> Reading the vault…</p>
            ) : advances.length === 0 ? (
              <p className="panel-note">No advances yet.</p>
            ) : (
              <div className="records-table">
                <div className="records-head">
                  <span>Payment</span><span>Advanced</span><span>Merchant</span><span>Status</span><span />
                </div>
                {advances.map((a) => (
                  <div className="records-row" key={a.paymentId}>
                    <div className="records-id">
                      <span className="records-badge"><Zap size={16} /></span>
                      <div className="records-cell"><strong>#{a.paymentId}</strong><small>1% advance fee</small></div>
                    </div>
                    <div className="records-cell num"><strong>{formatUsdc(a.amount.toString())}</strong></div>
                    <div className="records-cell"><strong>{shortAddr(a.merchant)}</strong></div>
                    <div>
                      {a.reconciled ? (
                        <span className="status-pill neutral">Reconciled</span>
                      ) : (
                        <span className="status-pill green">Outstanding{a.releasableAt ? ` · settles ${formatDate(a.releasableAt)}` : ""}</span>
                      )}
                    </div>
                    <span />
                  </div>
                ))}
              </div>
            )}
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Instant settlement (T plus 0)</h2></div>
            <ol className="how-steps">
              <li><span><Banknote size={15} /></span><div><strong>Buyer pays into escrow</strong><p>USDC is deposited into the USYC adapter and starts earning immediately.</p></div></li>
              <li><span><Zap size={15} /></span><div><strong>LP fronts the merchant</strong><p>The settlement vault advances the merchant net of a fee and takes assignment of the escrow claim.</p></div></li>
              <li><span><Landmark size={15} /></span><div><strong>Vault is repaid on release</strong><p>When the window closes, the claim pays the vault principal plus float yield; fees and yield minus refund losses set the LP share price.</p></div></li>
            </ol>
          </section>
        </div>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Your LP position</h2></div>
            <div className="earnings-grid">
              <div><span>Shares</span><strong>{vault ? formatUsdc(vault.myShares.toString()).replace(" USDC", "") : "…"}</strong></div>
              <div><span>Value</span><strong className="green-text">{vault ? formatUsdc(vault.myValue.toString()) : "…"}</strong></div>
              <div><span>Wallet</span><b><Wallet size={13} /> {wallet ? shortAddr(wallet) : "…"}</b></div>
              <div><span>Wallet balance</span><strong>{walletBalance !== null ? formatUsdc(walletBalance.toString()) : "…"}</strong></div>
            </div>
            <div className="vault-actions">
              <button type="button" className="dash-modal-primary" onClick={() => setDialog("deposit")}>
                <Send size={15} /> Deposit USDC
              </button>
              <button
                type="button"
                className="vault-secondary"
                onClick={() => setDialog("withdraw")}
                disabled={!vault || vault.myShares === 0n}
              >
                Withdraw
              </button>
            </div>
            <p className="panel-note">Deposits come from your provisioned Arc wallet. Fund it from the dashboard&apos;s Receive dialog first.</p>
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Onchain contracts</h2></div>
            <div className="address-list">
              {contracts.map((item) => (
                <div className="address-row" key={item.label}>
                  <div>
                    <span>{item.label}</span>
                    <code>{`${item.address.slice(0, 10)}…${item.address.slice(-8)}`}</code>
                  </div>
                  <a href={explorerAddressUrl(item.address)} target="_blank" rel="noreferrer">ArcScan <ArrowUpRight size={13} /></a>
                </div>
              ))}
            </div>
            <div className="panel-note">
              <Info size={16} />
              <span>On testnet the adapter is a MockUSYCAdapter that simulates yield-bearing shares. It swaps to a USYC Teller adapter once mainnet access is approved.</span>
            </div>
          </section>
        </div>
      </div>

      {dialog !== "none" && wallet && account && (
        <VaultDialog
          kind={dialog}
          accountId={account.accountId}
          maxShares={vault?.myShares ?? 0n}
          onClose={(didWrite) => {
            setDialog("none");
            if (didWrite) setRefreshKey((k) => k + 1);
          }}
        />
      )}
    </div>
  );
}

function VaultDialog({
  kind,
  accountId,
  maxShares,
  onClose,
}: {
  kind: "deposit" | "withdraw";
  accountId: number;
  maxShares: bigint;
  onClose: (didWrite: boolean) => void;
}) {
  const [amount, setAmount] = useState("");
  const [busy, setBusy] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    const parsed = Number(amount);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      setError(kind === "deposit" ? "Enter a positive USDC amount." : "Enter a positive share amount.");
      return;
    }
    const baseUnits = BigInt(Math.round(parsed * 1_000_000));
    if (kind === "withdraw" && baseUnits > maxShares) {
      setError("You do not have that many shares.");
      return;
    }
    setBusy(true);
    try {
      const hash = kind === "deposit" ? await vaultDeposit(accountId, baseUnits) : await vaultWithdraw(accountId, baseUnits);
      setTxHash(hash);
    } catch (e) {
      setError(e instanceof Error ? e.message : "The transaction failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="dash-modal-backdrop" role="dialog" aria-modal="true">
      <div className="dash-modal">
        <button className="dash-modal-close" type="button" onClick={() => onClose(txHash !== null)} aria-label="Close">
          <X size={16} />
        </button>
        {txHash ? (
          <>
            <h2>{kind === "deposit" ? "Deposited" : "Withdrawn"}</h2>
            <p>The transaction confirmed on Arc. Your position updates in a few seconds.</p>
            <a className="dash-modal-primary" href={explorerTxUrl(txHash)} target="_blank" rel="noreferrer">
              View transaction <ArrowUpRight size={15} />
            </a>
          </>
        ) : (
          <>
            <h2>{kind === "deposit" ? "Deposit USDC" : "Withdraw shares"}</h2>
            <p>
              {kind === "deposit"
                ? "You become a liquidity provider: your USDC funds T plus 0 merchant advances and earns fees plus float yield, less any policy-bounded refund losses."
                : "Withdraws idle USDC at the current share price. Capital tied up in outstanding advances stays until those claims settle."}
            </p>
            <label className="dash-modal-field">
              <span>{kind === "deposit" ? "Amount (USDC)" : "Shares"}</span>
              <input value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" inputMode="decimal" />
            </label>
            {error && <p className="dash-modal-error">{error}</p>}
            <button className="dash-modal-primary" type="button" onClick={submit} disabled={busy}>
              {busy ? <><Loader2 className="spin" size={15} /> Confirming…</> : <><Check size={15} /> Confirm</>}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
