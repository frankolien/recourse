"use client";

import { compute, verdictHash, type Policy, type VerdictInput } from "@recourse/engine";
import {
  ArrowLeft,
  ArrowUpRight,
  Check,
  CheckCircle2,
  ChevronRight,
  CircleHelp,
  FileCheck2,
  Fingerprint,
  FlaskConical,
  Github,
  LockKeyhole,
  RefreshCw,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  X,
} from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { formatUnits } from "viem";
import { BrandMark } from "@/components/brand-mark";
import { LottiePlayer } from "@/components/lottie-player";
import burstAnim from "@/lib/lottie/burst.json";
import loaderAnim from "@/lib/lottie/loader.json";
import pingAnim from "@/lib/lottie/ping.json";
import {
  arcTestnet,
  escrowAbi,
  escrowAddress,
  explorerPaymentUrl,
  publicClient,
  registryAbi,
  registryAddress,
} from "@/lib/contracts";

const claimNames = ["Not delivered", "Damaged", "Not as described", "Wrong item", "Other"];
const evidenceOptions = [
  { bit: 1, label: "Photo" },
  { bit: 2, label: "Description" },
  { bit: 4, label: "Tracking" },
  { bit: 8, label: "Video" },
];

interface PaymentData {
  buyer: `0x${string}`;
  merchant: `0x${string}`;
  beneficiary: `0x${string}`;
  policyId: bigint;
  amount: bigint;
  shares: bigint;
  paidAt: bigint;
  filedAt: bigint;
  claimType: number;
  evidenceMask: number;
  attType: number;
  attValue: number;
  evidenceRoot: `0x${string}`;
  verdictBps: number;
  status: number;
}

interface ChainVerdict {
  refundBps: number;
  requiresReturn: boolean;
  ruleIndex: number;
  matched: boolean;
}

interface VerificationData {
  payment: PaymentData;
  policy: Policy;
  policyHash: `0x${string}`;
  chainVerdict: ChainVerdict;
  chainVerdictHash: `0x${string}`;
}

function shortHash(value: string, lead = 8) {
  return `${value.slice(0, lead + 2)}…${value.slice(-6)}`;
}

function formatDate(timestamp: bigint) {
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(Number(timestamp) * 1000));
}

function verdictLabel(refundBps: number) {
  if (refundBps === 0) return "Denied";
  if (refundBps === 10_000) return "Refunded";
  return "Partial";
}

function verdictClass(refundBps: number) {
  if (refundBps === 0) return "denied";
  if (refundBps === 10_000) return "refunded";
  return "partial";
}

async function fetchVerification(paymentId: bigint): Promise<VerificationData> {
  const payment = (await publicClient.readContract({
    address: escrowAddress,
    abi: escrowAbi,
    functionName: "getPayment",
    args: [paymentId],
  })) as PaymentData;

  if (payment.policyId === 0n) throw new Error("Payment not found on Arc testnet.");

  const [rawPolicy, onchainPolicyHash, preview] = await Promise.all([
    publicClient.readContract({
      address: registryAddress,
      abi: registryAbi,
      functionName: "getPolicy",
      args: [payment.policyId],
    }),
    publicClient.readContract({
      address: registryAddress,
      abi: registryAbi,
      functionName: "policyHash",
      args: [payment.policyId],
    }),
    publicClient.readContract({
      address: escrowAddress,
      abi: escrowAbi,
      functionName: "previewVerdict",
      args: [paymentId],
    }),
  ]);

  const policy: Policy = {
    merchant: rawPolicy.merchant,
    disputeWindow: rawPolicy.disputeWindow,
    defaultRefundBps: rawPolicy.defaultRefundBps,
    rules: rawPolicy.rules.map((rule) => ({ ...rule })),
  };

  return {
    payment,
    policy,
    policyHash: onchainPolicyHash,
    chainVerdict: preview[0],
    chainVerdictHash: preview[1],
  };
}

export function VerifyPage({ paymentId }: { paymentId: bigint }) {
  const [data, setData] = useState<VerificationData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sandboxInput, setSandboxInput] = useState<VerdictInput | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const nextData = await fetchVerification(paymentId);
      setData(nextData);
      setSandboxInput({
        claimType: nextData.payment.claimType,
        evidenceMask: nextData.payment.evidenceMask,
        attType: nextData.payment.attType,
        attValue: nextData.payment.attValue,
        paidAt: nextData.payment.paidAt,
        filedAt: nextData.payment.filedAt,
      });
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not read Arc testnet.");
    } finally {
      setLoading(false);
    }
  }, [paymentId]);

  useEffect(() => {
    void load();
  }, [load]);

  const localInput = useMemo<VerdictInput | null>(() => {
    if (!data) return null;
    return {
      claimType: data.payment.claimType,
      evidenceMask: data.payment.evidenceMask,
      attType: data.payment.attType,
      attValue: data.payment.attValue,
      paidAt: data.payment.paidAt,
      filedAt: data.payment.filedAt,
    };
  }, [data]);

  const localVerdict = useMemo(() => {
    if (!data || !localInput) return null;
    const result = compute(data.policy, localInput);
    return { result, hash: verdictHash(data.policyHash, paymentId, localInput, result) };
  }, [data, localInput, paymentId]);

  const sandboxVerdict = useMemo(() => {
    if (!data || !sandboxInput) return null;
    const result = compute(data.policy, sandboxInput);
    return { result, hash: verdictHash(data.policyHash, paymentId, sandboxInput, result) };
  }, [data, sandboxInput, paymentId]);

  const hashesMatch = Boolean(data && localVerdict && data.chainVerdictHash === localVerdict.hash);
  const sandboxChanged = Boolean(localInput && sandboxInput && (
    localInput.claimType !== sandboxInput.claimType ||
    localInput.evidenceMask !== sandboxInput.evidenceMask ||
    localInput.attType !== sandboxInput.attType ||
    localInput.attValue !== sandboxInput.attValue
  ));

  function toggleEvidence(bit: number) {
    setSandboxInput((current) => current ? { ...current, evidenceMask: current.evidenceMask ^ bit } : current);
  }

  function resetSandbox() {
    if (!localInput) return;
    setSandboxInput({ ...localInput });
  }

  function loadEvidenceDemo() {
    if (!localInput) return;
    setSandboxInput({
      ...localInput,
      claimType: 1,
      evidenceMask: 0,
      attType: 0,
      attValue: 0,
    });
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <Link href="/dashboard" className="brand" aria-label="Recourse home">
          <BrandMark />
          <span>Recourse</span>
        </Link>
        <p className="brand-subtitle">Buyer protection for<br />USDC payments</p>

        <nav className="sidebar-nav" aria-label="Public navigation">
          <a className="nav-item active" href="#proof"><ShieldCheck size={18} /> Verify payment</a>
          <a className="nav-item" href="#policy"><FileCheck2 size={18} /> Policy rules</a>
          <a className="nav-item" href="#sandbox"><SlidersHorizontal size={18} /> Verdict sandbox</a>
        </nav>

        <div className="sidebar-bottom">
          <a className="nav-item" href="https://github.com/frankolien/recourse" target="_blank" rel="noreferrer"><Github size={18} /> Developers</a>
          <a className="nav-item" href="#how-it-works"><CircleHelp size={18} /> How it works</a>
          <div className="network-card">
            <span className="network-dot" />
            <div><strong>Arc Testnet</strong><span>Chain {arcTestnet.id}</span></div>
            <Check size={16} />
          </div>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <Link href="/dashboard" className="back-link"><ArrowLeft size={16} /> Back to app</Link>
          <div className="top-actions">
            <span className="live-pill"><LottiePlayer animationData={pingAnim} className="lottie-ping" /> Live on Arc</span>
            <a className="icon-button" href={explorerPaymentUrl} target="_blank" rel="noreferrer" aria-label="Open escrow on ArcScan"><ArrowUpRight size={18} /></a>
          </div>
        </header>

        <section className="hero">
          <div>
            <span className="eyebrow"><Sparkles size={14} /> Independent payment proof</span>
            <h1>Don’t trust the verdict.<br /><em>Recompute it.</em></h1>
            <p>Every result below comes from live Arc state and the public policy engine. No backend decides the outcome.</p>
          </div>
          <div className="payment-switcher">
            <span>Demo cases</span>
            <Link className={paymentId === 5n ? "case-link active" : "case-link"} href="/verify/5">#5 Refunded</Link>
            <Link className={paymentId === 6n ? "case-link active" : "case-link"} href="/verify/6">#6 Denied</Link>
          </div>
        </section>

        {loading ? (
          <div className="state-card"><LottiePlayer animationData={loaderAnim} className="lottie-loader" /><h2>Reading Arc testnet</h2><p>Fetching payment, policy, and onchain verdict.</p></div>
        ) : error ? (
          <div className="state-card error"><X size={24} /><h2>Verification unavailable</h2><p>{error}</p><button onClick={() => void load()}><RefreshCw size={15} /> Try again</button></div>
        ) : data && localVerdict && sandboxInput && sandboxVerdict ? (
          <>
            <section className="verdict-grid" id="proof">
              <article className={`verdict-card ${verdictClass(data.chainVerdict.refundBps)}`}>
                <div className="verdict-card-top">
                  <span className="card-label">Payment #{paymentId.toString()}</span>
                  <span className="verified-pill"><CheckCircle2 size={14} /> Verified</span>
                </div>
                <div className={`verdict-stamp ${verdictClass(data.chainVerdict.refundBps)}`}>
                  {verdictLabel(data.chainVerdict.refundBps)}
                </div>
                <div className="verdict-amount">
                  <span>{(data.chainVerdict.refundBps / 100).toFixed(0)}% buyer refund</span>
                  <strong>${formatUnits(data.payment.amount, 6)} <small>USDC</small></strong>
                </div>
                <div className="verdict-meta">
                  <span>Matched rule</span>
                  <strong>{data.chainVerdict.matched ? `Rule ${data.chainVerdict.ruleIndex + 1}` : "Policy default"}</strong>
                </div>
              </article>

              <article className="proof-card">
                <div className="section-heading">
                  <div className="icon-well green"><Fingerprint size={20} /></div>
                  <div><span>Cryptographic proof</span><h2>Two engines, one result</h2></div>
                </div>
                <div className="hash-row">
                  <div><span>Onchain eth_call</span><code>{shortHash(data.chainVerdictHash, 12)}</code></div>
                  <span className="source-tag">Solidity</span>
                </div>
                <div className="proof-connector"><span /><CheckCircle2 size={24} /><span /></div>
                <div className="hash-row">
                  <div><span>In-browser recompute</span><code>{shortHash(localVerdict.hash, 12)}</code></div>
                  <span className="source-tag soft">TypeScript</span>
                </div>
                <div className={hashesMatch ? "match-banner" : "match-banner mismatch"}>
                  {hashesMatch
                    ? <span className="match-check"><LottiePlayer animationData={burstAnim} className="match-burst" /><CheckCircle2 size={18} /></span>
                    : <X size={18} />}
                  <div><strong>{hashesMatch ? "Hashes match exactly" : "Hash mismatch"}</strong><span>{hashesMatch ? "The verdict is independently reproducible." : "The two engine results differ."}</span></div>
                </div>
              </article>
            </section>

            <section className="detail-grid">
              <article className="panel payment-panel">
                <div className="section-heading compact">
                  <div><span>Live payment data</span><h2>Protected payment</h2></div>
                  <a href={explorerPaymentUrl} target="_blank" rel="noreferrer">ArcScan <ArrowUpRight size={14} /></a>
                </div>
                <dl className="data-list">
                  <div><dt>Amount</dt><dd>${formatUnits(data.payment.amount, 6)} USDC</dd></div>
                  <div><dt>Status</dt><dd><span className="status-dot" /> Settled</dd></div>
                  <div><dt>Paid at</dt><dd>{formatDate(data.payment.paidAt)}</dd></div>
                  <div><dt>Buyer</dt><dd><code>{shortHash(data.payment.buyer)}</code></dd></div>
                  <div><dt>Merchant</dt><dd><code>{shortHash(data.payment.merchant)}</code></dd></div>
                  <div><dt>Evidence root</dt><dd><code>{shortHash(data.payment.evidenceRoot)}</code></dd></div>
                </dl>
              </article>

              <article className="panel policy-panel" id="policy">
                <div className="section-heading compact">
                  <div><span>Immutable policy #{data.payment.policyId.toString()}</span><h2>First match wins</h2></div>
                  <span className="locked"><LockKeyhole size={13} /> Onchain</span>
                </div>
                <div className="policy-hash"><span>Policy hash</span><code>{shortHash(data.policyHash, 12)}</code></div>
                <div className="rules-list">
                  {data.policy.rules.map((rule, index) => {
                    const matched = data.chainVerdict.matched && data.chainVerdict.ruleIndex === index;
                    return (
                      <div className={matched ? "rule-row matched" : "rule-row"} key={`${rule.claimType}-${index}`}>
                        <span className="rule-number">{index + 1}</span>
                        <div><strong>{claimNames[rule.claimType] ?? `Claim ${rule.claimType}`}</strong><span>{(rule.refundBps / 100).toFixed(0)}% refund, evidence mask {rule.requiredEvidenceMask}</span></div>
                        {matched ? <span className="matched-tag"><Check size={13} /> Matched</span> : <ChevronRight size={16} />}
                      </div>
                    );
                  })}
                  {!data.chainVerdict.matched && <div className="rule-row matched"><span className="rule-number">D</span><div><strong>Default outcome</strong><span>{(data.policy.defaultRefundBps / 100).toFixed(0)}% refund when no rule matches</span></div><span className="matched-tag"><Check size={13} /> Applied</span></div>}
                </div>
              </article>
            </section>

            <section className="sandbox-section" id="sandbox">
              <div className="sandbox-copy">
                <span className="eyebrow"><FlaskConical size={14} /> Interactive proof</span>
                <h2>Flip the evidence.<br />Watch policy decide.</h2>
                <p>This sandbox changes only your local inputs. It never writes to chain and it uses the same TypeScript engine that produced the matching hash above.</p>
                <div className="sandbox-actions">
                  <button className="preset-button" onClick={loadEvidenceDemo}><Sparkles size={15} /> Load evidence test</button>
                  <button className="reset-button" onClick={resetSandbox} disabled={!sandboxChanged}><RefreshCw size={15} /> Reset to chain inputs</button>
                </div>
              </div>
              <article className="sandbox-card">
                <div className="sandbox-controls">
                  <label>
                    <span>Claim type</span>
                    <select value={sandboxInput.claimType} onChange={(event) => setSandboxInput({ ...sandboxInput, claimType: Number(event.target.value) })}>
                      {claimNames.map((name, index) => <option key={name} value={index}>{name}</option>)}
                    </select>
                  </label>
                  <div className="evidence-control">
                    <span>Evidence attached</span>
                    <div className="evidence-chips">
                      {evidenceOptions.map((option) => {
                        const selected = (sandboxInput.evidenceMask & option.bit) === option.bit;
                        return <button className={selected ? "evidence-chip selected" : "evidence-chip"} key={option.bit} onClick={() => toggleEvidence(option.bit)}>{selected ? <Check size={14} /> : <span className="empty-check" />}{option.label}</button>;
                      })}
                    </div>
                  </div>
                </div>
                <div className={`sandbox-result ${verdictClass(sandboxVerdict.result.refundBps)}`}>
                  <div>
                    <span>Local outcome</span>
                    <strong>{verdictLabel(sandboxVerdict.result.refundBps)}</strong>
                    <small>{sandboxVerdict.result.matched ? `Rule ${sandboxVerdict.result.ruleIndex + 1} matched` : "No rule matched"}</small>
                  </div>
                  <div className="result-percentage">{(sandboxVerdict.result.refundBps / 100).toFixed(0)}<span>%</span></div>
                </div>
                <div className="sandbox-hash"><span>New local verdict hash</span><code>{shortHash(sandboxVerdict.hash, 12)}</code></div>
                {sandboxChanged && <p className="sandbox-note">Inputs differ from chain state, so this hash is expected to change.</p>}
              </article>
            </section>

            <section className="how-section" id="how-it-works">
              <div className="how-heading"><span>How verification works</span><h2>Four public steps. Zero trust required.</h2></div>
              <div className="how-grid">
                <div><span>01</span><FileCheck2 size={21} /><strong>Read the policy</strong><p>Fetch the immutable rule set pinned to this payment.</p></div>
                <div><span>02</span><ShieldCheck size={21} /><strong>Read the claim</strong><p>Load evidence, timing, and objective attestation inputs.</p></div>
                <div><span>03</span><FlaskConical size={21} /><strong>Compute twice</strong><p>Run Solidity by eth_call and TypeScript in this browser.</p></div>
                <div><span>04</span><Fingerprint size={21} /><strong>Compare hashes</strong><p>Matching bytes prove the result was not hand-picked.</p></div>
              </div>
            </section>

            <footer><div className="footer-brand"><BrandMark /><span>Recourse</span></div><p>Buyer protection for USDC payments on Arc.</p><span>Testnet prototype</span></footer>
          </>
        ) : null}
      </main>
    </div>
  );
}
