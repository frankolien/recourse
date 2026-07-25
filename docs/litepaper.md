# Recourse: Deterministic Buyer Protection for USDC Payments

**Litepaper v0.1 · July 2026 · Frank Olien**

Live implementation on Arc testnet (chain 5042002): [recourse-arc.vercel.app](https://recourse-arc.vercel.app)

## Abstract

Stablecoin payments are final. Finality protects merchants from fraud but leaves buyers with nothing when goods never arrive, which is a structural reason retail commerce has not moved to stablecoins. Card networks solve this with chargebacks: a human process that is slow, opaque, and gameable in both directions. Recourse proposes a different resolution primitive: disputes are computed, not decided. A merchant publishes an immutable refund policy onchain. Every payment escrows USDC under the exact policy hash it was made against, and the escrow keeps funds productive in a yield adapter while protected. When something goes wrong, a pure function of the policy, the claim, the evidence, an attested delivery fact, and timing produces the verdict. No party, including the operator, can override it, and anyone can recompute any verdict from public state and obtain the same bytes. A settlement vault lets liquidity providers advance merchant payouts to T+0 and absorb bounded refund risk in exchange for fees and float yield. The system is implemented end to end and running on Arc testnet, where all three sides of the market have settled real outcomes: a buyer refunded, a fraudulent claim denied, and a merchant paid the same minute their customer's funds entered a two week escrow.

## 1. Introduction

A USDC transfer settles in seconds and cannot be reversed. For payments between counterparties who trust each other this is a feature. For commerce between strangers it is the core defect: the buyer bears all delivery risk the moment they sign. The traditional answer, the card chargeback, resolves roughly by discretion: an agent applies rules the buyer never read, with an appeal process the merchant cannot predict. Friendly fraud costs merchants tens of billions annually precisely because the process is human and therefore persuadable.

Circle Research's Refund Protocol (April 2025) framed the open problems: how to give stablecoin payments a dispute path without reintroducing custodial discretion, how to keep escrowed funds productive, and how to give merchants immediate liquidity despite protection windows. Recourse is a working answer to these problems, built for the Build on Arc hackathon.

The design principle throughout: every decision that moves money must be a deterministic function of public state, fixed before the payment existed.

## 2. Design goals

1. **Determinism.** The refund outcome is a pure function. Two honest implementations on any hardware must produce identical verdict bytes.
2. **Prior consent.** All refund terms are pinned onchain before payment. Neither side can change the deal afterward.
3. **Public verifiability.** Any third party can recompute any verdict from chain state alone. Trust is replaced by recomputation.
4. **Narrow trust.** The only trusted input is a delivery fact asserted by an attestor, and the design bounds what a corrupt attestor could ever do.
5. **Productive escrow.** Protected funds earn yield rather than sitting idle.
6. **Instant merchant liquidity.** Protection windows must not force merchants to wait for their money.

## 3. System overview

Recourse consists of four contracts on Arc, three verdict engine implementations, and a deliberately powerless backend.

| Component | Role |
| --- | --- |
| PolicyRegistry | Stores immutable refund policies and their canonical hashes |
| RecourseEscrow | Holds payments, accepts disputes and attestations, resolves verdicts, moves funds |
| PolicyEngine | The verdict function, callable as a view for public recomputation |
| SettlementVault | LP capital that advances merchant payouts at T+0 and takes over escrow claims |
| Yield adapter | USYC style vault the escrow deposits into while funds are protected |

Three actors meet in the market. **Buyers** pay from a native iOS app whose signing key is generated in the device's secure storage and never leaves it; Face ID confirms every fund moving action. **Merchants** publish policies and generate checkout QR codes from the app or web workspace. **Liquidity providers** deposit USDC into the settlement vault from the app or web.

The backend indexes chain state, stores content addressed bytes, and holds no business logic. It cannot decide a verdict, alter an order, or forge evidence: everything it serves is either reproducible from public state or breaks a hash.

## 4. Immutable policies

A policy is registered once and never edited:

```
Policy {
  merchant        address
  disputeWindow   uint32   seconds a buyer has to file
  defaultRefundBps uint16  applied when no rule matches
  rules           Rule[]   max 16, evaluated in order, first match wins
}
```

Each rule matches a claim type against required evidence kinds and a required attestation, and yields a refund in basis points plus an optional return requirement. The registry stores keccak256 over the canonical encoding, and every payment records the policy id it was made under. A merchant who wants different terms publishes a new policy; existing payments keep the terms they were bought under, forever.

The live demo policy (id 4) has a 14 day window and two rules: a claim of Not delivered combined with an attested NOT_DELIVERED fact refunds 100 percent; a claim of Damaged supported by photo evidence refunds 100 percent with return of goods required. Anything else falls through to the default of 0 percent.

## 5. Protected payments and content addressing

A checkout is an exact JSON manifest: item name, description, image hash, price. The keccak256 of those exact bytes is the bytes32 orderRef stored by pay(). Product images are content addressed the same way, and a CDN mirror changes delivery, never trust, because the client rehashes whatever bytes arrive. A cross language golden fixture (0xa4e970942b2f79b3ef97bd7cbb6a64dd5c92ce63e6c6facc758792f69a88b7cd) is asserted in Rust, Swift, and TypeScript in the same repository.

The checkout QR encodes a universal link carrying the payment request. Any wallet count of buyers can scan the same QR: each pay() creates an independent payment with its own escrow position, protection window, and refund address fixed to the payer. Before requesting Face ID, the buyer's phone refetches the manifest, rehashes it, and cross checks merchant, amount, policy, and chain id against the QR. A single altered byte blocks payment.

On payment, USDC moves into the escrow, which deposits it into the yield adapter. Status proceeds Paid, then optionally Disputed, then Settled.

## 6. The verdict function

The core of Recourse is a pure function:

```
verdict = f(policy, VerdictInput)

VerdictInput {
  claimType     uint8
  evidenceMask  uint16
  attType       uint8
  attValue      uint8
  paidAt        uint64
  filedAt       uint64
}
```

Rules are evaluated in order; the first rule whose claim type, evidence requirements, attestation requirements, and timing constraints are all satisfied determines the refund basis points and return requirement. If no rule matches, the policy default applies. The engine returns the verdict together with a keccak256 verdict hash over its canonical encoding.

The same function exists three times: in Solidity as the canonical implementation that moves funds, in TypeScript recomputed inside any browser by the public verifier, and in Swift recomputed on the buyer's phone. Fourteen golden vectors plus engine generated hashes are asserted by forge and vitest in the same commit whenever the engine changes; the three implementations must agree byte for byte. The public verifier displays the Solidity verdict hash obtained by eth_call next to the hash computed in the visitor's own browser. The security claim is deliberately falsifiable: do not trust the verdict, recompute it.

Resolution is permissionless. Once a dispute is attested, resolve() applies the verdict: the refund share of escrowed funds returns to the original payer, the remainder plus its share of accrued yield goes to the beneficiary, and a 10 percent protocol share of yield goes to the treasury. A dispute that never receives an attestation can still be resolved after a fixed delay through the same deterministic path, so no one can stall a payment forever. An undisputed payment is released to the beneficiary by anyone after the window elapses.

## 7. Attestations: witness, not judge

The only external fact the system consumes is a delivery attestation: a typed, signed statement binding a payment id to a narrow fact such as DELIVERED or NOT_DELIVERED. The contract accepts attestations only from registered attestor keys, and the EIP-712 digest makes each attestation publicly attributable and replay proof.

The crucial design decision is what an attestor cannot do. It cannot choose a refund percentage, cannot resolve a claim type the policy does not cover, cannot alter a policy, and cannot touch funds. The meaning of any fact it asserts was fixed by the merchant's policy before payment. Attestations are inputs to the verdict function, never verdicts.

In the current deployment the attestor is a single clearly labeled demo key that stands in for carrier data. The production path is N of M independent attestations sourced from delivery oracles such as carrier APIs and proof of delivery signatures. The contract change is small precisely because the role was designed narrow.

## 8. Adversarial analysis

**A buyer who lies.** Receiving the goods and filing Not delivered achieves nothing: the matching rule requires an attested NOT_DELIVERED fact the buyer does not control. The claim falls through to the 0 percent default, escrow releases to the merchant, and the false claim remains permanently onchain, signed by the buyer, building a public fraud fingerprint. A Damaged claim requires returning the goods to collect.

**A merchant who never ships.** The attested NOT_DELIVERED fact matches the first rule and refunds 100 percent. The merchant cannot renegotiate, because the policy is immutable, and cannot stall, because resolution is permissionless.

**A corrupt attestor.** Bounded by construction: it can assert a wrong fact, but only within the vocabulary of facts, each one public and attributable. It can never set a percentage or reach uncovered claims. N of M attestation dilutes this residual power further.

**A malicious operator or backend.** The backend serves bytes whose hashes the chain already committed to, and evidence uploads require an EIP-712 signature proving the caller is the onchain buyer. A hostile backend can at worst degrade liveness; it cannot alter any outcome. The public verifier reads the chain directly and works with the backend offline.

## 9. The settlement vault

Protection windows lock merchant revenue for days. The settlement vault converts that wait into a priced risk market. LPs deposit USDC for shares. The vault owner enrolls merchants with a fee in basis points and a per merchant exposure cap. For an eligible Paid payment, advance() pays the merchant the amount net of fee immediately and assigns the escrow claim to the vault, flipping the payment's beneficiary. When the payment settles, reconcile() books the outcome: full escrow proceeds plus yield if no refund, the loss absorbed by the vault if a refund occurred.

Share accounting values outstanding advances at par: totalAssets equals idle USDC plus outstanding, so the share price moves on booked fees, received yield, and realized losses rather than on marks. LP return decomposes as advance fees plus float yield minus refund losses, and every term is inspectable onchain. Exposure caps bound the loss any single merchant can impose on the pool, and the immutable policies bound the refund risk of each advanced payment.

In the live deployment: a merchant enrolled at 100 bps with a 50 USDC cap received 6.93 USDC net at T+0 against a 7 USDC payment sitting in a 14 day escrow, and the share price moved from 1.000312 to 1.009064 on the booked fee.

## 10. Productive escrow

Escrowed funds are never idle. The escrow deposits into a USYC style yield adapter on payment and redeems at settlement. Accrued yield is split at settlement: 90 percent to the beneficiary of the payment, 10 percent to the protocol treasury. Buyers lose nothing to the mechanism; merchants and the vault earn the float their revenue generates while protected. The current adapter is a mock with the production interface, pending real world asset access.

## 11. Implementation status

Everything described above is deployed and exercised on Arc testnet (chain 5042002):

| Contract | Address |
| --- | --- |
| RecourseEscrow | 0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0 |
| PolicyRegistry | 0x94f8551fbE43aB919D87c3951394b148c914430E |
| SettlementVault | 0x5d8a3000866493f5D0B5B07a4Ad63ADE3B02054D |
| Yield adapter (mock USYC) | 0x2336AaBE139b7F426aF63f713b9f93CD3FFC6204 |
| USDC (Circle, native) | 0x3600000000000000000000000000000000000000 |

Settled outcomes, each verifiable on the public verifier and on Arc explorers:

- **Refund enforced.** Payment 13, paid from a physical iPhone, disputed as Not delivered with Face ID signed evidence, attested, and resolved at 100 percent: the buyer received exactly 5.20 USDC back. Attest tx 0xb85cfab7d1cc6ad6ff6de4180096fec302f231cbd6e4ff1ed043efa3e2c35348, resolve tx 0x6c9eabc8bfd889215771ac6315dfacfb663a2ee934411f8b5d96cac48f485351.
- **Fraudulent claim denied.** Payment 15, disputed as Wrong item, a claim its policy does not cover: 0 percent by the deterministic default, merchant paid with yield. Resolve tx 0x209890e66483ce0eb2f53f5a6f4a63e05242389d8d631a8c5e6b7b86875e5408.
- **Merchant paid at T+0.** Payment 14 advanced by the vault the same minute it entered escrow. Advance tx 0xa2411d96a41fcca1dd9075b619dfa53f91012ad2380b3a22eeb3dfe06b4fb1b8.

The client surface is a native SwiftUI iOS app (device wallet, camera and universal link checkout, evidence capture, LP deposits, public verification) and a Next.js web app (merchant workspace, vault, public verifier that recomputes verdicts in the browser).

## 12. Limitations and roadmap

This is a testnet prototype and says so. The attestor is a single demo key behind operator auth; production is N of M delivery oracles. The yield adapter mocks USYC pending real access. Wallet keys are per device; production binds device keys to accounts under an account abstraction design. The vault omits share inflation hardening. Inventory is not tracked onchain, so overselling is a fulfillment failure the protection absorbs rather than prevents. Contracts are unaudited. The path to production is credible precisely because the trust model was drawn first: every step hardens a boundary that already exists.

## 13. References

1. Circle Research, Refund Protocol, April 2025.
2. Arc network documentation, chain 5042002.
3. Recourse repository, live application, and public verifier: recourse-arc.vercel.app.
