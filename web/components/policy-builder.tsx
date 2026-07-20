"use client";

import {
  compilePolicy,
  compute,
  policyHash,
  PolicyCompileError,
  type ClaimTypeName,
  type EvidenceName,
  type PolicySpec,
  type RuleSpec,
} from "@recourse/engine";
import {
  ArrowLeft,
  Check,
  Copy,
  FlaskConical,
  Plus,
  Trash2,
} from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import seed from "../../deployments/seed-arc-testnet.json";

const MERCHANT = seed.merchant as `0x${string}`;
const DAY = 86_400;

const CLAIM_LABELS: Record<ClaimTypeName, string> = {
  NOT_DELIVERED: "Not delivered",
  DAMAGED: "Damaged",
  NOT_AS_DESCRIBED: "Not as described",
  WRONG_ITEM: "Wrong item",
  OTHER: "Other",
};
const CLAIM_OPTIONS = Object.keys(CLAIM_LABELS) as ClaimTypeName[];

const EVIDENCE_LABELS: Record<EvidenceName, string> = {
  PHOTO: "Photo",
  DESCRIPTION: "Description",
  TRACKING_REF: "Tracking",
  VIDEO: "Video",
};
const EVIDENCE_OPTIONS = Object.keys(EVIDENCE_LABELS) as EvidenceName[];

// Attestation is authored as a single choice: none, or a required delivery status.
const ATTESTATION_OPTIONS = [
  { value: "NONE", label: "No attestation" },
  { value: "DELIVERED", label: "Attested delivered" },
  { value: "NOT_DELIVERED", label: "Attested not delivered" },
  { value: "UNKNOWN", label: "Attested unknown" },
] as const;
type AttestationChoice = (typeof ATTESTATION_OPTIONS)[number]["value"];

function attestationFromChoice(choice: AttestationChoice): RuleSpec["attestation"] {
  return choice === "NONE" ? null : { type: "DELIVERY_STATUS", equals: choice };
}

function choiceFromAttestation(attestation: RuleSpec["attestation"]): AttestationChoice {
  return attestation ? attestation.equals : "NONE";
}

const DEFAULT_SPEC: PolicySpec = {
  version: 1,
  disputeWindowSeconds: 14 * DAY,
  defaultRefundBps: 0,
  rules: [
    { id: "not-delivered-full", claimType: "NOT_DELIVERED", requiredEvidence: [], attestation: { type: "DELIVERY_STATUS", equals: "NOT_DELIVERED" }, claimWindowSeconds: 14 * DAY, refundBps: 10_000, requiresReturn: false },
    { id: "damaged-full", claimType: "DAMAGED", requiredEvidence: ["PHOTO"], attestation: null, claimWindowSeconds: 3 * DAY, refundBps: 10_000, requiresReturn: true },
  ],
};

const EMPTY_RULE: RuleSpec = { claimType: "NOT_DELIVERED", requiredEvidence: [], attestation: null, claimWindowSeconds: 14 * DAY, refundBps: 10_000, requiresReturn: false };

function verdictLabel(refundBps: number) {
  if (refundBps === 0) return "Denied";
  if (refundBps === 10_000) return "Refunded";
  return "Partial";
}

function verdictTone(refundBps: number) {
  if (refundBps === 0) return "red";
  if (refundBps === 10_000) return "green";
  return "amber";
}

export function PolicyBuilder() {
  const [spec, setSpec] = useState<PolicySpec>(DEFAULT_SPEC);
  const [testClaim, setTestClaim] = useState<ClaimTypeName>("NOT_DELIVERED");
  const [testEvidence, setTestEvidence] = useState<EvidenceName[]>([]);
  const [testAttestation, setTestAttestation] = useState<AttestationChoice>("NOT_DELIVERED");
  const [copied, setCopied] = useState(false);

  const compiled = useMemo(() => {
    try {
      const policy = compilePolicy(spec, MERCHANT);
      return { policy, hash: policyHash(policy), error: null as string | null };
    } catch (error) {
      const message = error instanceof PolicyCompileError ? error.message : "Could not compile this policy.";
      return { policy: null, hash: null, error: message };
    }
  }, [spec]);

  const verdict = useMemo(() => {
    if (!compiled.policy) return null;
    const evidenceMask = testEvidence.reduce((mask, name) => mask | { PHOTO: 1, DESCRIPTION: 2, TRACKING_REF: 4, VIDEO: 8 }[name], 0);
    const attType = testAttestation === "NONE" ? 0 : 1;
    const attValue = testAttestation === "NONE" ? 0 : { UNKNOWN: 0, DELIVERED: 1, NOT_DELIVERED: 2 }[testAttestation];
    return compute(compiled.policy, {
      claimType: CLAIM_OPTIONS.indexOf(testClaim),
      evidenceMask,
      attType,
      attValue,
      paidAt: 0n,
      filedAt: 0n,
    });
  }, [compiled.policy, testClaim, testEvidence, testAttestation]);

  function patchPolicy(patch: Partial<PolicySpec>) {
    setSpec((current) => ({ ...current, ...patch }));
  }

  function patchRule(index: number, patch: Partial<RuleSpec>) {
    setSpec((current) => ({
      ...current,
      rules: current.rules.map((rule, i) => (i === index ? { ...rule, ...patch } : rule)),
    }));
  }

  function addRule() {
    setSpec((current) => (current.rules.length >= 16 ? current : { ...current, rules: [...current.rules, { ...EMPTY_RULE }] }));
  }

  function removeRule(index: number) {
    setSpec((current) => ({ ...current, rules: current.rules.filter((_, i) => i !== index) }));
  }

  function toggleRuleEvidence(index: number, name: EvidenceName) {
    setSpec((current) => ({
      ...current,
      rules: current.rules.map((rule, i) => {
        if (i !== index) return rule;
        const has = rule.requiredEvidence.includes(name);
        return { ...rule, requiredEvidence: has ? rule.requiredEvidence.filter((e) => e !== name) : [...rule.requiredEvidence, name] };
      }),
    }));
  }

  function toggleTestEvidence(name: EvidenceName) {
    setTestEvidence((current) => (current.includes(name) ? current.filter((e) => e !== name) : [...current, name]));
  }

  async function copyJson() {
    await navigator.clipboard.writeText(JSON.stringify(spec, null, 2));
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <Link href="/policies" className="back-link"><ArrowLeft size={15} /> Policies</Link>
          <h1>New policy</h1>
          <p>Author refund rules, watch them compile to the exact onchain hash, and test a claim before publishing.</p>
        </div>
      </header>

      <div className="two-col">
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Policy settings</h2></div>
            <div className="builder-grid">
              <label className="field-row">
                <span>Dispute window (days)</span>
                <input type="number" min={0} value={Math.round(spec.disputeWindowSeconds / DAY)} onChange={(event) => patchPolicy({ disputeWindowSeconds: Math.max(0, Number(event.target.value)) * DAY })} />
              </label>
              <label className="field-row">
                <span>Default refund (%)</span>
                <input type="number" min={0} max={100} value={spec.defaultRefundBps / 100} onChange={(event) => patchPolicy({ defaultRefundBps: Math.min(100, Math.max(0, Number(event.target.value))) * 100 })} />
              </label>
            </div>
          </section>

          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Rules</h2><p>Evaluated top to bottom, first match wins</p></div>
              <button className="page-cta ghost" onClick={addRule} disabled={spec.rules.length >= 16}><Plus size={15} /> Add rule</button>
            </div>

            {spec.rules.map((rule, index) => (
              <article className="builder-rule" key={index}>
                <div className="builder-rule-head">
                  <strong>Rule {index + 1}</strong>
                  <button className="rule-remove" onClick={() => removeRule(index)} aria-label={`Remove rule ${index + 1}`}><Trash2 size={14} /></button>
                </div>
                <div className="builder-grid">
                  <label className="field-row">
                    <span>Claim type</span>
                    <select value={rule.claimType} onChange={(event) => patchRule(index, { claimType: event.target.value as ClaimTypeName })}>
                      {CLAIM_OPTIONS.map((name) => <option key={name} value={name}>{CLAIM_LABELS[name]}</option>)}
                    </select>
                  </label>
                  <label className="field-row">
                    <span>Attestation</span>
                    <select value={choiceFromAttestation(rule.attestation)} onChange={(event) => patchRule(index, { attestation: attestationFromChoice(event.target.value as AttestationChoice) })}>
                      {ATTESTATION_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                  </label>
                  <label className="field-row">
                    <span>Claim window (days)</span>
                    <input type="number" min={0} value={Math.round(rule.claimWindowSeconds / DAY)} onChange={(event) => patchRule(index, { claimWindowSeconds: Math.max(0, Number(event.target.value)) * DAY })} />
                  </label>
                  <label className="field-row">
                    <span>Refund (%)</span>
                    <input type="number" min={0} max={100} value={rule.refundBps / 100} onChange={(event) => patchRule(index, { refundBps: Math.min(100, Math.max(0, Number(event.target.value))) * 100 })} />
                  </label>
                </div>
                <div className="field-row">
                  <span>Required evidence</span>
                  <div className="evidence-chips">
                    {EVIDENCE_OPTIONS.map((name) => {
                      const selected = rule.requiredEvidence.includes(name);
                      return <button className={selected ? "evidence-chip selected" : "evidence-chip"} key={name} onClick={() => toggleRuleEvidence(index, name)} type="button">{selected ? <Check size={14} /> : <span className="empty-check" />}{EVIDENCE_LABELS[name]}</button>;
                    })}
                  </div>
                </div>
                <div className="toggle-row">
                  <div><strong>Requires return</strong><small>Buyer must return the item to be refunded</small></div>
                  <button type="button" role="switch" aria-checked={rule.requiresReturn} aria-label="Requires return" className={rule.requiresReturn ? "toggle-pill on" : "toggle-pill"} onClick={() => patchRule(index, { requiresReturn: !rule.requiresReturn })} />
                </div>
              </article>
            ))}

            {spec.rules.length === 0 && <p className="builder-empty">No rules yet. Every claim falls to the default refund.</p>}
          </section>
        </div>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Policy hash</h2></div>
            {compiled.error ? (
              <div className="panel-note error-note">{compiled.error}</div>
            ) : (
              <>
                <div className="policy-hash"><span>Compiles to</span><code>{compiled.hash ? `${compiled.hash.slice(0, 14)}…${compiled.hash.slice(-8)}` : ""}</code></div>
                <p className="builder-hint">This is the exact hash registerPolicy would pin onchain for merchant {MERCHANT.slice(0, 6)}…{MERCHANT.slice(-4)}. Change a rule and it changes.</p>
                <button className="page-cta ghost" onClick={() => void copyJson()}>{copied ? <><Check size={15} /> Copied</> : <><Copy size={15} /> Copy policy JSON</>}</button>
              </>
            )}
          </section>

          {compiled.policy && (
            <section className="dash-panel">
              <div className="panel-heading compact"><h2>Compiled rules</h2></div>
              <div className="rules-list">
                {compiled.policy.rules.map((rule, index) => (
                  <div className="rule-row" key={index}>
                    <span className="rule-number">{index + 1}</span>
                    <div>
                      <strong>{CLAIM_LABELS[CLAIM_OPTIONS[rule.claimType] ?? "OTHER"]}</strong>
                      <span>{(rule.refundBps / 100).toFixed(0)}% refund · mask {rule.requiredEvidenceMask} · att {rule.attType}/{rule.attExpected} · {Math.round(rule.claimWindow / DAY)}d{rule.requiresReturn ? " · return" : ""}</span>
                    </div>
                  </div>
                ))}
                <div className="rule-row"><span className="rule-number">D</span><div><strong>Default</strong><span>{(spec.defaultRefundBps / 100).toFixed(0)}% refund when no rule matches</span></div></div>
              </div>
            </section>
          )}

          {compiled.policy && (
            <section className="dash-panel">
              <div className="panel-heading compact"><h2><FlaskConical size={15} /> Test a claim</h2></div>
              <div className="builder-grid">
                <label className="field-row">
                  <span>Claim type</span>
                  <select value={testClaim} onChange={(event) => setTestClaim(event.target.value as ClaimTypeName)}>
                    {CLAIM_OPTIONS.map((name) => <option key={name} value={name}>{CLAIM_LABELS[name]}</option>)}
                  </select>
                </label>
                <label className="field-row">
                  <span>Attested status</span>
                  <select value={testAttestation} onChange={(event) => setTestAttestation(event.target.value as AttestationChoice)}>
                    {ATTESTATION_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                  </select>
                </label>
              </div>
              <div className="field-row">
                <span>Evidence attached</span>
                <div className="evidence-chips">
                  {EVIDENCE_OPTIONS.map((name) => {
                    const selected = testEvidence.includes(name);
                    return <button className={selected ? "evidence-chip selected" : "evidence-chip"} key={name} onClick={() => toggleTestEvidence(name)} type="button">{selected ? <Check size={14} /> : <span className="empty-check" />}{EVIDENCE_LABELS[name]}</button>;
                  })}
                </div>
              </div>
              {verdict && (
                <div className={`builder-verdict ${verdictTone(verdict.refundBps)}`}>
                  <div><span>Outcome</span><strong>{verdictLabel(verdict.refundBps)}</strong><small>{verdict.matched ? `Rule ${verdict.ruleIndex + 1} matched` : "No rule matched, default applied"}</small></div>
                  <div className="builder-verdict-pct">{(verdict.refundBps / 100).toFixed(0)}<span>%</span></div>
                </div>
              )}
            </section>
          )}
        </div>
      </div>
    </div>
  );
}
