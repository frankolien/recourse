---
project: recourse
doc: PRD
version: 0.1.0
date: 2026-07-20
event: Build on Arc / Programmable Money Hackathon (Encode x Circle), DeFi track
deadline: Final submission Sunday 2026-08-09 AoE, submit by 2026-08-07
author: GiFTED (@goodylili) with Claude
---

# Recourse: Product Requirements

## 1. One-liner

Buyer protection for USDC. Protected checkouts escrow into yield-bearing USYC, pinned to hashed machine-readable refund policies. Disputes resolve deterministically with verdicts anyone can recompute, and an instant settlement vault pays merchants at T+0 by underwriting dispute-window risk.

## 2. The wound and why now

Stablecoin payments are cash: send it and pray. Card networks charge merchants 2 to 3 percent and a large share of that buys one thing, recourse. Circle Research published Refund Protocol in April 2025 (circle.com/blog/refund-protocol-non-custodial-dispute-resolution-for-stablecoin-payments) and then listed, in public, the problems that stopped it from becoming a product: arbiters with too much discretion, refund address specification, per-payment escrow gas costs, escrowed funds earning nothing, and no contract-wallet support.

Every one of those has an Arc-native answer in July 2026:

| Refund Protocol open problem | Recourse answer on Arc |
|---|---|
| Malicious or discretionary arbiter | Policy-as-code. The contract computes verdicts from a hashed policy. The arbiter is demoted to an evidence attestor with zero outcome discretion. |
| Unproductive escrowed funds | Escrow sweeps into USYC (tokenized Treasury MMF, live on Arc testnet via the Teller contract). Escrow earns T-bill yield during the dispute window. |
| Gas cost of per-payment escrow | Arc has sub-cent, predictable, USDC-denominated gas. Per-payment escrow is economical. |
| Merchant cash flow locked in escrow | Instant settlement vault. LPs pay the merchant at T+0, take assignment of the escrow claim, and earn fee plus yield. |
| Refund address specification | refundTo fixed at pay time, per the original design, kept simple with EOAs for the MVP. |

Arc mainnet is expected summer 2026. The judges are Circle and Arc ecosystem people evaluating what should exist at launch. The published rubric signals: a working prototype deployed on Arc, clear use of Circle developer tools, a real use case with a path to production, and quality of execution over complexity.

## 3. Users and jobs

**Buyer (native iPhone app).** Pay a merchant with protection, hold receipts, understand exactly what the refund policy guarantees before paying, file a dispute with photo evidence from the camera, watch the verdict compute, get refunded.

**Merchant (Next.js web dashboard).** Author a refund policy once, publish it onchain, take protected payments via link, QR, or the checkout SDK, get paid at T+0 through the vault, watch disputes resolve without touching them, collect escrow yield on the happy path.

**LP (web, one page).** Deposit USDC into the settlement vault, earn advance fees plus USYC float yield minus refund losses, see the APY decomposition honestly.

**Attestor (backend bot, demo-only console).** Signs EIP-712 statements about objective facts only (delivery status). Cannot decide outcomes. Exists to prove the "arbiter has no discretion" claim.

## 4. Product surfaces

1. **Native iPhone app (buyer only).** SwiftUI scan-to-pay, receipts, policy card, dispute filing with camera, and verdict view. Android is deferred and may use Flutter later.
2. **Next.js web.** Merchant dashboard, policy builder, dispute console (read and evidence view), LP vault page, public verify page at /verify/[paymentId], and a demo storefront using the SDK.
3. **React checkout SDK.** A small package exposing a RecourseCheckout component and a QR payload generator so any storefront can take protected payments.
4. **Rust backend.** Event indexer, REST API, evidence blob store (hash onchain, blob offchain), demo attestor bot, demo data seeder. No business logic.
5. **Solidity contracts on Arc testnet.** PolicyRegistry, PolicyEngine (canonical verdict logic), RecourseEscrow, SettlementVault, YieldAdapter (USYC or Mock).

## 5. Core flows

**F1. Merchant setup.** Connect wallet on web. Author policy in the builder (form produces policy JSON). Compiler encodes JSON to onchain rule structs and calls PolicyRegistry.registerPolicy. Policy is immutable; edits create a new policyId. Merchant gets a payment link, a QR, and an SDK snippet. Optionally enrolls in the vault for T+0 settlement (feeBps shown upfront).

**F2. Protected checkout.** Buyer scans QR in the app (or pays on web via SDK). App renders the policy card: human-readable rules decoded from chain ("Damaged item, photo within 3 days: full refund"). Buyer approves USDC and calls escrow.pay(policyId, amount, orderRef). Escrow pins policyHash, records refundTo = buyer, sweeps principal into the yield adapter, emits Paid.

**F3. Instant settlement.** Vault (or a keeper) observes Paid for an enrolled merchant, calls vault.advance(paymentId): pays merchant amount minus feeBps immediately, then assigns itself beneficiary of the escrow claim. Merchant cash flow is now independent of the dispute window.

**F4. Release (happy path).** Dispute window passes with no dispute. Anyone calls escrow.release(paymentId): adapter redeems principal plus yield, beneficiary receives principal plus its yield share, protocol takes a small yield fee. Vault reconciles its outstanding advance.

**F5. Dispute.** Within the window, buyer files from the app: picks a claim type, attaches evidence (photos via camera, description). App uploads blobs to the backend, gets keccak256 hashes back, then calls escrow.fileDispute(paymentId, claimType, evidence[]). If the matching rule requires a delivery attestation, the attestor bot signs and submits one. After attestation (or a short resolveDelay), anyone calls escrow.resolve(paymentId): the PolicyEngine computes the verdict onchain, funds split per refundBps, verdict and verdictHash are emitted. Deterministic: same policy, same inputs, same verdict, forever.

**F6. Verify (the demo weapon).** Anyone opens /verify/[paymentId]. The page fetches the payment and policy from chain, runs the TypeScript mirror of the engine locally in the browser, cross-checks with an eth_call to the onchain engine, and shows both verdict hashes matching. Flip an evidence input in the sandbox and watch the verdict change on its own. Provable beats impressive.

**F7. LP flow.** Deposit and withdraw USDC on /vault. Stats show TVL, outstanding advances, realized losses, fee income, float yield, and net APY.

## 6. Policy schema v0 (authoring format)

Merchants author JSON; the compiler encodes it to onchain structs. The policyHash covers the onchain encoding, not the JSON.

```json
{
  "version": 1,
  "disputeWindowSeconds": 1209600,
  "defaultRefundBps": 0,
  "rules": [
    {
      "id": "not-delivered-full",
      "claimType": "NOT_DELIVERED",
      "requiredEvidence": [],
      "attestation": { "type": "DELIVERY_STATUS", "equals": "NOT_DELIVERED" },
      "claimWindowSeconds": 1209600,
      "refundBps": 10000,
      "requiresReturn": false
    },
    {
      "id": "damaged-full",
      "claimType": "DAMAGED",
      "requiredEvidence": ["PHOTO"],
      "attestation": null,
      "claimWindowSeconds": 259200,
      "refundBps": 10000,
      "requiresReturn": true
    },
    {
      "id": "not-as-described-half",
      "claimType": "NOT_AS_DESCRIBED",
      "requiredEvidence": ["PHOTO", "DESCRIPTION"],
      "attestation": null,
      "claimWindowSeconds": 604800,
      "refundBps": 5000,
      "requiresReturn": false
    }
  ]
}
```

Verdict semantics: rules evaluate in array order, first match wins. A rule matches when claimType equals, all requiredEvidence bits are present in the submitted evidence mask, the attestation requirement (if any) is satisfied by the stored attested value, and filedAt is within paidAt plus claimWindowSeconds. No match falls to defaultRefundBps. Max 16 rules per policy for gas sanity.

## 7. Vault mechanics (the DeFi engine)

USDC vault with shares. Merchants are enrolled with a feeBps (flat 50 bps for MVP) and an exposure cap. advance() pays merchant net and books the claim at par as an outstanding asset. On release, the vault receives principal plus yield share and reconciles. On a refund verdict, the vault absorbs the refunded portion; the loss flows into share price. LP APY equals fee income plus USYC float yield minus refund losses, and because policies are machine-readable, worst-case exposure per payment is computable at advance time. That is the pitch line: LPs underwrite dispute-window risk with deterministic bounds.

## 8. Non-goals for the hackathon

No fiat on-ramp, no KYC, no multi-arbiter governance, no mainnet deployment, no merchant mobile app, no subscriptions or mandates, no StableFX or confidential transfer dependencies, no risk-based dynamic vault pricing (flat fee only), no contract-wallet (EIP-1271) support. Each is a roadmap line in the deck, not a build item.

## 9. Demo script (3-minute beats)

1. (0:00) The wound: "Stablecoin payments are cash. Circle spec'd the fix in April 2025 and published the four problems that stopped it. This is those four problems solved, on Arc." One slide, four problems, four answers.
2. (0:25) Buyer moment, filmed on the phone: scan QR, policy card, pay. Receipt lands with a live yield ticker on the escrow.
3. (0:55) Merchant moment: dashboard shows T+0 payout already settled via the vault. "Protection never touched their cash flow."
4. (1:20) Dispute: buyer photographs a damaged item in-app, files. Attestor attests delivery. resolve() fires, verdict stamps REFUNDED 100 percent, rule id shown.
5. (1:50) The provable beat, on /verify: "Did I hardcode that? Watch." Recompute the verdict in-browser, hashes match the chain. Flip the evidence input, verdict collapses to deny on its own.
6. (2:20) LP page: APY decomposition, fees plus T-bill float yield minus losses. "LPs underwrite dispute risk with deterministic bounds."
7. (2:40) Close: Circle tool coverage (Arc, USDC, USYC, Gateway pay-in), path to production (PSPs, checkout SDK), mainnet is weeks away, this should exist at launch.

## 10. Rubric mapping

| Rubric signal | Recourse |
|---|---|
| Working prototype deployed on Arc | All contracts on Arc testnet, chainId 5042002, live seeded data |
| Clear use of Circle developer tools | USDC (payment and gas), USYC via Teller, Gateway/CCTP cross-chain pay-in (stretch), Circle faucet flows |
| Real use case, path to production | Merchant checkout SDK, PSP integration story, accelerator-ready |
| Quality of execution over complexity | Small deterministic contract surface, polished buyer app, public verifiability |

## 11. Design direction

Light editorial, in the house style: cream and off-white grounds, ink-dark text, generous whitespace, serif display for headlines with a grotesk body, minimal chrome. Product motif: receipts and ledgers. Perforated receipt edges on payment cards, tabular monospace numerals for amounts, a physical stamp treatment for verdicts (REFUNDED, DENIED, PARTIAL) with a subtle stamp-down animation. One accent color, a deep ledger green, red reserved for the DENIED stamp. The same palette and type across app, dashboard, deck, and video. Consistency is the cheapest form of polish.

## 12. Milestones against checkpoints

| Window | Milestone | Checkpoint |
|---|---|---|
| Jul 20 to 21 | M0: repo scaffold, Foundry init, golden vectors v1, PolicyRegistry plus PolicyEngine | |
| Jul 22 to 24 | M1: Escrow, adapters, vault, forge tests green against vectors, deploy to Arc testnet | |
| Jul 25 to 26 | M2: TS engine parity, verify page skeleton, seed script, progress writeup | CP2 Sun Jul 26 |
| Jul 27 to 31 | M3: Rust indexer, API, evidence store, attestor bot; merchant dashboard and policy builder | |
| Aug 1 to 3 | M4: native iPhone buyer app core (pay, receipts, dispute with camera, verdict) | |
| Aug 4 to 5 | M5: vault UI, SDK package, stretch gate (Gateway pay-in, EIP-3009 single-tx pay, agent-track demo) | |
| Aug 6 to 8 | M6: Remotion video, deck, final seed data, rehearse aloud, deploy, submit | Final Sun Aug 9, submit by Aug 7 |

## 13. Risks and fallbacks

USYC testnet access requires approval before the Teller can be called: apply on day one, build behind an IYieldAdapter interface, ship MockUSYCAdapter (identical interface, simulated 4.5 percent APY) as insurance; the narrative survives either path. USDC on Arc has 6 decimals on the ERC-20 interface and 18 as native gas: product logic uses the ERC-20 interface only. Do not depend on StableFX or confidential transfers. If contracts slip past Jul 25, cut vault UI polish before engine parity. If the iPhone app slips past Aug 3, ship dispute filing only on mobile and let receipts fall back to web. At CP2, scan the Encode project gallery for refund-adjacent entries; if any exist, lean the framing harder into the deterministic engine plus the vault, which nobody else will have.

## 14. Open questions

Whether Arc testnet USDC exposes EIP-3009 receiveWithAuthorization (would enable single-signature pay; verify onchain before promising it). Final resolveDelay value for demo pacing (default 60 seconds). Whether to show EURC refunds as a one-slide roadmap tease (yes in deck, no in build).
