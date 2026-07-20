"use client";

import { type Policy } from "@recourse/engine";
import {
  ArrowUpRight,
  Check,
  LoaderCircle,
  LockKeyhole,
  Plus,
  RefreshCw,
  X,
} from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  explorerAddressUrl,
  publicClient,
  registryAbi,
  registryAddress,
} from "@/lib/contracts";

const claimNames = ["Not delivered", "Damaged", "Not as described", "Wrong item", "Other"];
const POLICY_ID = 1n;

interface PolicyData {
  policy: Policy;
  hash: `0x${string}`;
}

function shortHash(value: string) {
  return `${value.slice(0, 14)}…${value.slice(-8)}`;
}

async function fetchPolicy(): Promise<PolicyData> {
  const [rawPolicy, hash] = await Promise.all([
    publicClient.readContract({
      address: registryAddress,
      abi: registryAbi,
      functionName: "getPolicy",
      args: [POLICY_ID],
    }),
    publicClient.readContract({
      address: registryAddress,
      abi: registryAbi,
      functionName: "policyHash",
      args: [POLICY_ID],
    }),
  ]);

  return {
    policy: {
      merchant: rawPolicy.merchant,
      disputeWindow: rawPolicy.disputeWindow,
      defaultRefundBps: rawPolicy.defaultRefundBps,
      rules: rawPolicy.rules.map((rule) => ({ ...rule })),
    },
    hash,
  };
}

export function PoliciesPage() {
  const [data, setData] = useState<PolicyData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setData(await fetchPolicy());
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not read Arc testnet.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Policies</h1>
          <p>Refund rules are immutable and pinned to each payment. First matching rule wins.</p>
        </div>
        <button className="page-cta ghost"><Plus size={15} /> New policy</button>
      </header>

      {loading ? (
        <div className="dash-panel state-inline"><LoaderCircle className="spin" size={22} /><div><strong>Reading policy from Arc</strong><p>Fetching policy #1 and its onchain hash.</p></div></div>
      ) : error ? (
        <div className="dash-panel state-inline error"><X size={22} /><div><strong>Policy unavailable</strong><p>{error}</p></div><button className="page-cta ghost" onClick={() => void load()}><RefreshCw size={14} /> Retry</button></div>
      ) : data ? (
        <>
          <section className="metric-grid cols-3">
            <article className="metric-card"><span>Rules</span><strong>{data.policy.rules.length}</strong><small>Evaluated top to bottom</small></article>
            <article className="metric-card"><span>Default refund</span><strong>{(data.policy.defaultRefundBps / 100).toFixed(0)}%</strong><small>When no rule matches</small></article>
            <article className="metric-card"><span>Dispute window</span><strong>{Math.round(data.policy.disputeWindow / 86400)} days</strong><small>{data.policy.disputeWindow.toLocaleString()} seconds</small></article>
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Policy #1</h2><p>Immutable rule set, first match wins</p></div>
              <span className="locked"><LockKeyhole size={13} /> Onchain</span>
            </div>
            <div className="policy-hash"><span>Policy hash</span><code>{shortHash(data.hash)}</code></div>
            <div className="rules-list">
              {data.policy.rules.map((rule, index) => (
                <div className="rule-row" key={`${rule.claimType}-${index}`}>
                  <span className="rule-number">{index + 1}</span>
                  <div>
                    <strong>{claimNames[rule.claimType] ?? `Claim ${rule.claimType}`}</strong>
                    <span>{(rule.refundBps / 100).toFixed(0)}% refund · evidence mask {rule.requiredEvidenceMask} · {rule.requiresReturn ? "return required" : "no return"}</span>
                  </div>
                  <span className="matched-tag"><Check size={13} /> Active</span>
                </div>
              ))}
              <div className="rule-row">
                <span className="rule-number">D</span>
                <div><strong>Default outcome</strong><span>{(data.policy.defaultRefundBps / 100).toFixed(0)}% refund when no rule matches</span></div>
              </div>
            </div>
          </section>

          <div className="two-col">
            <div className="panel-note">
              <LockKeyhole size={16} />
              <span>Editing a live policy would change results, so policies are immutable once published. The visual policy builder writes a new policy and returns its id.</span>
            </div>
            <div className="address-row" style={{ borderBottom: 0 }}>
              <div><span>Policy registry</span><code>{shortHash(registryAddress)}</code></div>
              <a href={explorerAddressUrl(registryAddress)} target="_blank" rel="noreferrer">ArcScan <ArrowUpRight size={13} /></a>
            </div>
          </div>

          <Link className="page-cta ghost" href="/verify/5"><ArrowUpRight size={15} /> Open this policy in the verifier</Link>
        </>
      ) : null}
    </div>
  );
}
