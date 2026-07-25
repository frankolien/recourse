"use client";

import {
  ArrowUpRight,
  Check,
  ChevronRight,
  CircleDollarSign,
  CircleHelp,
  ClipboardList,
  Code2,
  Copy,
  FileCheck2,
  Headphones,
  Loader2,
  LockKeyhole,
  MessageCircle,
  PackageCheck,
  Send,
  Shield,
  ShieldCheck,
  Store,
  X,
} from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  API_BASE,
  formatDate,
  formatUsdc,
  getPayments,
  getPolicies,
  shortAddr,
  statusLabel,
  type ApiPayment,
  type ApiPolicy,
} from "@/lib/api";
import { explorerTxUrl } from "@/lib/contracts";
import { sendUsdc, useArcWallet, useUsdcBalance } from "@/lib/wallet";
import { useLive } from "@/lib/use-live";
import { useSession } from "@/components/session-provider";
import { ProtectionMark } from "@/components/live-pulse";

const learnCards = [
  { icon: <FileCheck2 size={21} />, title: "How protection works", copy: "Understand policies, escrow and disputes", href: "/policies" },
  { icon: <Store size={21} />, title: "For merchants", copy: "Get paid instantly while buyers stay protected", href: "/vault" },
  { icon: <Code2 size={21} />, title: "For developers", copy: "Integrate Recourse into your app", href: "https://github.com/frankolien/recourse" },
  { icon: <LockKeyhole size={21} />, title: "Security and audits", copy: "Built on Arc with best in class security", href: "/verify/5" },
];

interface OrderMeta {
  name: string;
  imageHash: string | null;
}

// Fetch verified order names and image hashes for rows that carry an orderRef; the
// manifest is the same hash-bound document the phone verifies, the web just displays it.
function useOrderMeta(payments: ApiPayment[] | null): Record<number, OrderMeta> {
  const [meta, setMeta] = useState<Record<number, OrderMeta>>({});
  useEffect(() => {
    if (!payments) return;
    let alive = true;
    const targets = payments.filter((p) => p.orderRef).slice(0, 24);
    Promise.all(
      targets.map((p) =>
        fetch(`${API_BASE}/api/orders/${p.orderRef}`)
          .then((r) => (r.ok ? r.json() : null))
          .then((m) => [p.paymentId, m] as const)
          .catch(() => [p.paymentId, null] as const),
      ),
    ).then((pairs) => {
      if (!alive) return;
      const next: Record<number, OrderMeta> = {};
      for (const [id, manifest] of pairs) {
        if (manifest?.itemName) {
          next[id] = { name: manifest.itemName, imageHash: manifest.imageHash ?? null };
        }
      }
      setMeta(next);
    });
    return () => {
      alive = false;
    };
  }, [payments]);
  return meta;
}

function OrderArtwork({ meta }: { meta: OrderMeta | undefined }) {
  if (meta?.imageHash) {
    return (
      /* Content-addressed product photo; served via the CDN redirect. */
      // eslint-disable-next-line @next/next/no-img-element
      <img className="merchant-icon order-photo" src={`${API_BASE}/api/orders/image/${meta.imageHash}`} alt="" />
    );
  }
  return <span className="merchant-icon cloud"><PackageCheck size={18} /></span>;
}

function usdcDisplay(balance: bigint | null): { dollars: string; units: string } {
  if (balance === null) return { dollars: "…", units: "reading Arc" };
  const units = formatUsdc(balance.toString());
  return { dollars: `$${units.replace(" USDC", "")}`, units };
}

function involvesAddress(p: ApiPayment, address: string | null): boolean {
  if (!address) return false;
  const a = address.toLowerCase();
  return p.merchant.toLowerCase() === a || p.buyer.toLowerCase() === a;
}

function protectionEnd(p: ApiPayment, policies: ApiPolicy[] | null): number | null {
  const policy = policies?.find((x) => x.policyId === p.policyId);
  return policy ? p.paidAt + policy.disputeWindow : null;
}

type WalletDialog = "none" | "send" | "receive";

export function DashboardPage() {
  const { account } = useSession();
  const greetingName = account?.givenName ?? "there";
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";

  const wallet = useArcWallet(account?.accountId);
  const balance = useUsdcBalance(wallet);
  const paymentsLive = useLive(getPayments);
  const policiesLive = useLive(getPolicies);
  const payments = paymentsLive.data;
  const policies = policiesLive.data;
  const orderMeta = useOrderMeta(payments);

  const [dialog, setDialog] = useState<WalletDialog>("none");
  const [copied, setCopied] = useState(false);

  const mine = useMemo(() => (payments ?? []).filter((p) => involvesAddress(p, wallet)), [payments, wallet]);
  const scoped = mine.length > 0;
  // A fresh wallet has no history; show the network's latest real payments instead of
  // an empty desert, labeled for what they are.
  const tableRows = useMemo(() => {
    const source = scoped ? mine : (payments ?? []);
    return [...source].sort((a, b) => b.paidAt - a.paidAt).slice(0, 5);
  }, [scoped, mine, payments]);

  const active = useMemo(() => mine.filter((p) => p.status === 1), [mine]);
  const disputedRows = useMemo(() => {
    const source = scoped ? mine : (payments ?? []);
    return source.filter((p) => p.status === 2).sort((a, b) => b.filedAt - a.filedAt).slice(0, 2);
  }, [scoped, mine, payments]);
  const networkActive = useMemo(() => (payments ?? []).filter((p) => p.status === 1), [payments]);
  const escrowScope = scoped ? active : networkActive;
  const totalEscrowed = useMemo(
    () => escrowScope.reduce((sum, p) => sum + BigInt(p.amount), 0n),
    [escrowScope],
  );
  const totalSpent = useMemo(
    () =>
      (payments ?? [])
        .filter((p) => wallet && p.buyer.toLowerCase() === wallet.toLowerCase())
        .reduce((sum, p) => sum + BigInt(p.amount), 0n),
    [payments, wallet],
  );
  const activeProtected = useMemo(
    () => active.reduce((sum, p) => sum + BigInt(p.amount), 0n),
    [active],
  );
  const activity = useMemo(() => {
    const source = scoped ? mine : (payments ?? []);
    const events: { key: string; icon: React.ReactNode; title: string; detail: string; at: number; tone: string }[] = [];
    for (const p of source) {
      const name = orderMeta[p.paymentId]?.name ?? `Payment #${p.paymentId}`;
      events.push({ key: `paid-${p.paymentId}`, icon: <PackageCheck size={15} />, title: `Protected payment: ${name}`, detail: formatUsdc(p.amount), at: p.paidAt, tone: "soft" });
      if (p.filedAt) events.push({ key: `disp-${p.paymentId}`, icon: <ClipboardList size={15} />, title: `Dispute filed on #${p.paymentId}`, detail: name, at: p.filedAt, tone: "orange" });
      if (p.status === 3) {
        const bps = p.refundBps ?? p.verdictBps ?? 0;
        events.push({ key: `set-${p.paymentId}`, icon: <Check size={15} />, title: bps >= 10000 ? `Refunded 100%: #${p.paymentId}` : bps > 0 ? `Partial refund: #${p.paymentId}` : `Released to merchant: #${p.paymentId}`, detail: name, at: Math.floor(new Date(p.updatedAt).getTime() / 1000), tone: bps > 0 ? "green" : "gray" });
      }
    }
    return events.sort((a, b) => b.at - a.at).slice(0, 5);
  }, [scoped, mine, payments, orderMeta]);

  const balanceText = usdcDisplay(balance);
  const now = Math.floor(Date.now() / 1000);

  function copyAddress() {
    if (!wallet) return;
    navigator.clipboard.writeText(wallet);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  }

  return (
    <>
      <header className="dash-header">
        <div>
          <h1>{greeting}, {greetingName} <span>👋</span></h1>
          <p>Here is what is happening with your protected payments.</p>
        </div>
      </header>

      <section className="summary-grid">
        <article className="balance-card">
          <div className="summary-label">USDC Balance <CircleHelp size={13} /></div>
          <strong>{balanceText.dollars}</strong>
          <span>{balanceText.units}</span>
          {wallet && (
            <button className="wallet-address" type="button" onClick={copyAddress} title={wallet}>
              {copied ? <Check size={12} /> : <Copy size={12} />} {shortAddr(wallet)} · Arc wallet
            </button>
          )}
          <div className="balance-actions">
            <button type="button" onClick={() => setDialog("send")}><Send size={13} /> Send</button>
            <button type="button" onClick={() => setDialog("receive")}>Receive</button>
            <Link href="/payments">Pay</Link>
          </div>
        </article>

        <Link className="summary-card protected-summary" href="/protection">
          <div className="summary-label">Protected Payments</div>
          <strong><em>{active.length}</em> active</strong>
          <b>{formatUsdc(activeProtected.toString()).replace(" USDC", "")} <span>protected</span></b>
          <p>{scoped ? "For this wallet" : "None for this wallet yet"}</p>
          <ProtectionMark className="summary-icon green" />
        </Link>

        <Link className="summary-card action-summary" href="/disputes">
          <div className="summary-label">Action Needed</div>
          <strong><em>{mine.filter((p) => p.status === 2).length}</em></strong>
          <b>{mine.some((p) => p.status === 2) ? "Open dispute" : "Nothing waiting on you"}</b>
          <p>{mine.find((p) => p.status === 2) ? `Payment #${mine.find((p) => p.status === 2)!.paymentId}` : "All clear"}</p>
          <div className="summary-icon orange"><ClipboardList size={21} /></div>
        </Link>

        <Link className="summary-card spent-summary" href="/payments">
          <div className="summary-label">Total Spent <ArrowUpRight size={14} /></div>
          <strong>${formatUsdc(totalSpent.toString()).replace(" USDC", "")}</strong>
          <p>As buyer, all time</p>
        </Link>
      </section>

      <div className="dash-content-grid">
        <div className="dash-primary-column">
          <section className="dash-panel protections-panel">
            <div className="panel-heading">
              <div>
                <h2>{scoped ? "Your protected payments" : "Latest protected payments on Arc"}</h2>
                <p>{scoped ? "Payments involving your Arc wallet" : "Live from the Arc indexer. Fund your wallet to join them."}</p>
              </div>
              <Link href="/protection">View all protections</Link>
            </div>
            {paymentsLive.loading ? (
              <p className="panel-note"><Loader2 className="spin" size={14} /> Reading the Arc indexer…</p>
            ) : paymentsLive.error ? (
              <p className="panel-note">The indexer is unreachable right now. Nothing here is cached or invented; try again shortly.</p>
            ) : tableRows.length === 0 ? (
              <p className="panel-note">No protected payments yet. Create a checkout from the Recourse iOS app to see it here.</p>
            ) : (
              <div className="protection-table">
                <div className="protection-head">
                  <span>Order</span><span>Amount</span><span>Protection ends</span><span>Status</span><span>Progress</span><span />
                </div>
                {tableRows.map((p) => {
                  const end = protectionEnd(p, policies);
                  const window = end ? end - p.paidAt : 0;
                  const progress = end ? Math.min(100, Math.max(0, Math.round(((now - p.paidAt) / window) * 100))) : 0;
                  const status = statusLabel(p.status);
                  return (
                    <Link className="protection-row" href={`/verify/${p.paymentId}`} key={p.paymentId}>
                      <div className="merchant-cell">
                        <OrderArtwork meta={orderMeta[p.paymentId]} />
                        <span><strong>{orderMeta[p.paymentId]?.name ?? `Payment #${p.paymentId}`}</strong><small>{shortAddr(p.merchant)}</small></span>
                      </div>
                      <div><strong>${formatUsdc(p.amount).replace(" USDC", "")}</strong><small>{formatUsdc(p.amount)}</small></div>
                      <div><strong>{end ? formatDate(end) : "Pending"}</strong><small>paid {formatDate(p.paidAt)}</small></div>
                      <div><span className="active-status"><ShieldCheck size={14} /> {status.label}</span></div>
                      <div className="progress-cell"><span><i style={{ width: `${progress}%` }} /></span><small>{progress}% of window</small></div>
                      <ChevronRight size={16} />
                    </Link>
                  );
                })}
              </div>
            )}
          </section>

          <section className="dash-panel disputes-panel">
            <div className="panel-heading compact">
              <div><h2>Disputes</h2><p>Deterministic outcomes, previewable before settlement</p></div>
              <Link href="/disputes">View all disputes</Link>
            </div>
            {disputedRows.length === 0 ? (
              <p className="panel-note">No open disputes{scoped ? " for this wallet" : " on the network"} right now.</p>
            ) : (
              disputedRows.map((p) => (
                <Link className="dispute-row" href={`/verify/${p.paymentId}`} key={p.paymentId}>
                  <div className="dispute-order">
                    <span className="dispute-icon"><LockKeyhole size={17} /></span>
                    <div>
                      <strong>{orderMeta[p.paymentId]?.name ?? `Payment #${p.paymentId}`}</strong>
                      <small>vs {shortAddr(p.merchant)}</small>
                      <b>Under review</b>
                    </div>
                  </div>
                  <div className="dispute-info">
                    <span>Claim</span>
                    <strong>{["Not delivered", "Damaged", "Not as described", "Wrong item", "Other"][p.claimType] ?? "Other"}</strong>
                    <small>Filed {formatDate(p.filedAt)}</small>
                  </div>
                  <div className="dispute-info due">
                    <span>Engine preview</span>
                    <strong>{p.matched ? `${Math.round((p.refundBps ?? 0) / 100)}% refund` : "No rule matched"}</strong>
                    <small>{p.matched ? `rule ${p.ruleIndex}` : "policy default applies"}</small>
                  </div>
                  <div className="dispute-timeline">
                    <div className="timeline-line"><i className="done" /><i className="review" /><i /><i /></div>
                    <div className="timeline-labels">
                      <span><b>Paid</b><small>{formatDate(p.paidAt)}</small></span>
                      <span><b>Disputed</b><small>{formatDate(p.filedAt)}</small></span>
                      <span><b>Attestation</b><small>{p.attType ? "Recorded" : "Pending"}</small></span>
                      <span><b>Resolved</b><small>Pending</small></span>
                    </div>
                  </div>
                </Link>
              ))
            )}
          </section>

          <section className="learn-section">
            <h2>Learn about Recourse</h2>
            <div className="learn-grid">
              {learnCards.map((item) => (
                item.href.startsWith("http")
                  ? <a key={item.title} href={item.href} target="_blank" rel="noreferrer"><span>{item.icon}</span><div><strong>{item.title}</strong><p>{item.copy}</p></div></a>
                  : <Link key={item.title} href={item.href}><span>{item.icon}</span><div><strong>{item.title}</strong><p>{item.copy}</p></div></Link>
              ))}
            </div>
          </section>
        </div>

        <aside className="dash-right-rail">
          <section className="dash-panel activity-panel">
            <div className="panel-heading compact"><h2>Recent activity</h2><Link href="/payments">View all</Link></div>
            <div className="activity-list">
              {activity.length === 0 ? (
                <p className="panel-note">Activity appears as payments happen on Arc.</p>
              ) : (
                activity.map((item) => (
                  <div className="activity-item" key={item.key}>
                    <span className={`activity-icon ${item.tone}`}>{item.icon}</span>
                    <div><strong>{item.title}</strong>{item.detail && <small>{item.detail}</small>}</div>
                    <time>{formatDate(item.at)}</time>
                  </div>
                ))
              )}
            </div>
          </section>

          <section className="dash-panel earnings-panel">
            <div className="panel-heading compact"><h2>Escrow earnings</h2><Link href="/vault">View details</Link></div>
            <div className="earnings-grid">
              <div><span>Total escrowed</span><strong>{formatUsdc(totalEscrowed.toString())}</strong></div>
              <div><span>Earnings</span><strong className="green-text">Accruing via USYC</strong></div>
              <div><span>Yield source</span><b><CircleDollarSign size={13} /> USYC</b></div>
              <div><span>Scope</span><strong>{scoped ? "Your wallet" : "Whole network"}</strong></div>
            </div>
          </section>

          <section className="support-panel">
            <div><h2>Need help with a payment?</h2><p>Our support team is here to help you resolve issues quickly and fairly.</p><Link href="/support" className="support-cta">Contact support</Link></div>
            <div className="support-art"><MessageCircle size={29} /><Headphones size={58} /><Shield size={28} /></div>
          </section>
        </aside>
      </div>

      {dialog !== "none" && wallet && account && (
        <WalletDialogView
          kind={dialog}
          address={wallet}
          accountId={account.accountId}
          onClose={() => setDialog("none")}
        />
      )}
    </>
  );
}

function WalletDialogView({
  kind,
  address,
  accountId,
  onClose,
}: {
  kind: "send" | "receive";
  address: `0x${string}`;
  accountId: number;
  onClose: () => void;
}) {
  const [to, setTo] = useState("");
  const [amount, setAmount] = useState("");
  const [busy, setBusy] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  async function submitSend() {
    setError(null);
    const target = to.trim() as `0x${string}`;
    if (!/^0x[0-9a-fA-F]{40}$/.test(target)) {
      setError("Enter a valid Arc address (0x + 40 hex characters).");
      return;
    }
    const parsed = Number(amount);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      setError("Enter a positive USDC amount.");
      return;
    }
    const baseUnits = BigInt(Math.round(parsed * 1_000_000));
    setBusy(true);
    try {
      const hash = await sendUsdc(accountId, target, baseUnits);
      setTxHash(hash);
    } catch (e) {
      setError(e instanceof Error ? e.message : "The transfer failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="dash-modal-backdrop" role="dialog" aria-modal="true">
      <div className="dash-modal">
        <button className="dash-modal-close" type="button" onClick={onClose} aria-label="Close">
          <X size={16} />
        </button>
        {kind === "receive" ? (
          <>
            <h2>Receive USDC</h2>
            <p>This is your Arc wallet, created with your account. Send USDC to it from any Arc wallet, including the Recourse iOS app (Home, then the paper plane).</p>
            <code className="dash-modal-address">{address}</code>
            <button
              className="dash-modal-primary"
              type="button"
              onClick={() => {
                navigator.clipboard.writeText(address);
                setCopied(true);
                setTimeout(() => setCopied(false), 1600);
              }}
            >
              {copied ? <><Check size={15} /> Copied</> : <><Copy size={15} /> Copy address</>}
            </button>
          </>
        ) : txHash ? (
          <>
            <h2>Sent</h2>
            <p>The transfer confirmed on Arc.</p>
            <a className="dash-modal-primary" href={explorerTxUrl(txHash)} target="_blank" rel="noreferrer">
              View transaction <ArrowUpRight size={15} />
            </a>
          </>
        ) : (
          <>
            <h2>Send USDC</h2>
            <p>A direct transfer from your Arc wallet. Direct sends are not protected; use a checkout QR for protected payments.</p>
            <label className="dash-modal-field">
              <span>Recipient address</span>
              <input value={to} onChange={(e) => setTo(e.target.value)} placeholder="0x…" spellCheck={false} />
            </label>
            <label className="dash-modal-field">
              <span>Amount (USDC)</span>
              <input value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" inputMode="decimal" />
            </label>
            {error && <p className="dash-modal-error">{error}</p>}
            <button className="dash-modal-primary" type="button" onClick={submitSend} disabled={busy}>
              {busy ? <><Loader2 className="spin" size={15} /> Sending…</> : <><Send size={15} /> Send USDC</>}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
