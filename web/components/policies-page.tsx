"use client";

import { type Policy } from "@recourse/engine";
import {
  ArrowUpRight,
  Check,
  LockKeyhole,
  Plus,
  RefreshCw,
  X,
} from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { LottiePlayer } from "@/components/lottie-player";
import loaderAnim from "@/lib/lottie/loader.json";
import {
  explorerAddressUrl,
  publicClient,
  registryAbi,
  registryAddress,
} from "@/lib/contracts";

// The registry holds both vocabularies: parcel claims start at 0, agent claims at
// 5 (docs/agent-settlement.md A1). Unknown values still render, just unnamed.
const claimNames: Record<number, string> = {
  0: "Not delivered",
  1: "Damaged",
  2: "Not as described",
  3: "Wrong item",
  4: "Other",
  5: "Not served",
  6: "Schema violation",
  7: "SLA breach",
  8: "Partial failure",
};

const evidenceNames: [number, string][] = [
  [1, "photo"],
  [2, "description"],
  [4, "tracking ref"],
  [8, "video"],
  [16, "call log"],
  [32, "schema failure"],
  [64, "latency series"],
  [128, "unreachable probe"],
];

function describeEvidence(mask: number): string {
  const named = evidenceNames.filter(([bit]) => (mask & bit) === bit).map(([, name]) => name);
  return named.length ? named.join(" + ") : "no evidence required";
}

function describeWindow(seconds: number): string {
  if (seconds >= 86_400) return `${Math.round(seconds / 86_400)} days`;
  if (seconds >= 3_600) return `${Math.round(seconds / 3_600)} hours`;
  if (seconds >= 60) return `${Math.round(seconds / 60)} minutes`;
  return `${seconds} seconds`;
}

interface PolicyData {
  id: bigint;
  policy: Policy;
  hash: `0x${string}`;
}

function shortHash(value: string) {
  return `${value.slice(0, 14)}…${value.slice(-8)}`;
}

async function fetchPolicy(policyId: bigint): Promise<PolicyData> {
  const [rawPolicy, hash] = await Promise.all([
    publicClient.readContract({
      address: registryAddress,
      abi: registryAbi,
      functionName: "getPolicy",
      args: [policyId],
    }),
    publicClient.readContract({
      address: registryAddress,
      abi: registryAbi,
      functionName: "policyHash",
      args: [policyId],
    }),
  ]);

  return {
    id: policyId,
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
  const [count, setCount] = useState<bigint | null>(null);
  // Null means "whichever is newest", which is what a merchant who just published
  // one is looking for. A chosen id pins the view instead.
  const [selected, setSelected] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (wanted: bigint | null, isRefresh = false) => {
    if (isRefresh) setRefreshing(true);
    else setLoading(true);
    setError(null);
    try {
      const total = await publicClient.readContract({
        address: registryAddress,
        abi: registryAbi,
        functionName: "policyCount",
      });
      setCount(total);
      if (total === 0n) {
        setData(null);
        return;
      }
      // A policy registered since the last read moves the newest id, so refreshing
      // without a pinned selection is what surfaces one just published.
      const id = wanted && wanted <= total ? wanted : total;
      setData(await fetchPolicy(id));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not read Arc testnet.");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load(selected);
  }, [load, selected]);

  const ids = count ? Array.from({ length: Number(count) }, (_, i) => BigInt(i + 1)).reverse() : [];

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Policies</h1>
          <p>Refund rules are immutable and pinned to each payment. First matching rule wins.</p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <button
            className="page-cta ghost"
            onClick={() => void load(selected, true)}
            disabled={loading || refreshing}
          >
            <RefreshCw size={14} className={refreshing ? "spin" : undefined} />
            {refreshing ? "Refreshing" : "Refresh"}
          </button>
          <Link className="page-cta ghost" href="/policies/new"><Plus size={15} /> New policy</Link>
        </div>
      </header>

      {ids.length > 1 ? (
        <div className="rules-list" style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
          {ids.map((id) => (
            <button
              key={id.toString()}
              className="page-cta ghost"
              aria-current={data?.id === id ? "true" : undefined}
              style={data?.id === id ? { borderColor: "currentColor" } : undefined}
              onClick={() => setSelected(id)}
            >
              #{id.toString()}
            </button>
          ))}
        </div>
      ) : null}

      {loading ? (
        <div className="dash-panel state-inline"><LottiePlayer animationData={loaderAnim} className="lottie-loader-sm" /><div><strong>Reading policies from Arc</strong><p>Fetching the registry and the onchain hash.</p></div></div>
      ) : error ? (
        <div className="dash-panel state-inline error"><X size={22} /><div><strong>Policy unavailable</strong><p>{error}</p></div><button className="page-cta ghost" onClick={() => void load(selected, true)}><RefreshCw size={14} /> Retry</button></div>
      ) : count === 0n ? (
        <div className="dash-panel state-inline"><LockKeyhole size={22} /><div><strong>No policies yet</strong><p>Publish one and it appears here. Registering writes to Arc, so it shows up once the transaction confirms.</p></div><Link className="page-cta ghost" href="/policies/new"><Plus size={15} /> New policy</Link></div>
      ) : data ? (
        <>
          <section className="metric-grid cols-3">
            <article className="metric-card"><span>Rules</span><strong>{data.policy.rules.length}</strong><small>Evaluated top to bottom</small></article>
            <article className="metric-card"><span>Default refund</span><strong>{(data.policy.defaultRefundBps / 100).toFixed(0)}%</strong><small>When no rule matches</small></article>
            <article className="metric-card"><span>Dispute window</span><strong>{describeWindow(data.policy.disputeWindow)}</strong><small>{data.policy.disputeWindow.toLocaleString()} seconds</small></article>
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div>
                <h2>Policy #{data.id.toString()}</h2>
                <p>Immutable rule set, first match wins{count && data.id === count ? " · most recent" : ""}</p>
              </div>
              <span className="locked"><LockKeyhole size={13} /> Onchain</span>
            </div>
            <div className="policy-hash"><span>Policy hash</span><code>{shortHash(data.hash)}</code></div>
            <div className="rules-list">
              {data.policy.rules.map((rule, index) => (
                <div className="rule-row" key={`${rule.claimType}-${index}`}>
                  <span className="rule-number">{index + 1}</span>
                  <div>
                    <strong>{claimNames[rule.claimType] ?? `Claim ${rule.claimType}`}</strong>
                    <span>
                      {(rule.refundBps / 100).toFixed(0)}% refund · {describeEvidence(rule.requiredEvidenceMask)}
                      {rule.attType !== 0 ? ` · attested value ${rule.attExpected}` : ""} · {rule.requiresReturn ? "return required" : "no return"}
                    </span>
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
        </>
      ) : null}
    </div>
  );
}
