<p align="center">
  <img src="web/public/brand/recourse-mark.png" width="72" alt="Recourse" />
</p>

<h1 align="center">Recourse</h1>
<p align="center"><b>Deterministic buyer protection for USDC payments on Arc.</b></p>
<p align="center">
  <a href="https://testflight.apple.com/join/rWWg1wCb">iOS beta on TestFlight</a> ·
  <a href="https://recourse-arc.vercel.app">Live web app</a> ·
  <a href="https://recourse-arc.vercel.app/verify/13">Public verifier</a> ·
  <a href="https://recourse-arc.vercel.app/litepaper">Litepaper</a> ·
  <a href="https://api.frankolien.com/health">Live API</a>
</p>

---

Card networks give buyers chargebacks. Crypto gives buyers nothing: a USDC payment is final the moment it lands, which is exactly why most people will not use it for commerce. Circle Research published the Refund Protocol (April 2025) and listed its open problems publicly. Recourse is a working answer to them, built on Arc for the Build on Arc hackathon.

The core idea: **disputes are computed, not decided.** A merchant publishes an immutable refund policy onchain. Every payment escrows USDC under the exact policy hash it was made against. When something goes wrong, a pure function of (policy, claim, evidence, attestation, timing) produces the verdict. No support agent, no platform discretion, no backend that can put a thumb on the scale. Anyone can recompute any verdict from public state and get the same bytes.

## What actually happened on this testnet

This is not a demo of what would happen. All three sides of the marketplace have settled real outcomes on Arc (chain 5042002):

**A buyer got refunded.** Payment 13 ($5.20, paid from a physical iPhone) was disputed as Not delivered with Face ID-signed photo evidence, attested NOT_DELIVERED, and resolved: rule 0 matched, verdict 10000 bps, and the buyer's wallet received exactly 5.20 USDC back.
- attest [`0xb85cfab7..c35348`](https://testnet.arcscan.app/tx/0xb85cfab7d1cc6ad6ff6de4180096fec302f231cbd6e4ff1ed043efa3e2c35348) · resolve [`0x6c9eabc8..485351`](https://testnet.arcscan.app/tx/0x6c9eabc8bfd889215771ac6315dfacfb663a2ee934411f8b5d96cac48f485351)

**A bad claim got denied, provably.** Payment 15 was disputed as Wrong item, which its policy does not cover. No rule matched, the deterministic default (0 bps) applied, and no attestation could have changed it. The merchant received the escrowed funds plus the yield they earned while disputed.
- resolve [`0x209890e6..5e5408`](https://testnet.arcscan.app/tx/0x209890e66483ce0eb2f53f5a6f4a63e05242389d8d631a8c5e6b7b86875e5408)

**A merchant got paid at T+0.** Payment 14 ($7.00) sits in escrow until Aug 7, but the settlement vault advanced the merchant $6.93 (net of a 1% fee) the same minute and took assignment of the escrow claim. LP share price moved from 1.000312 to 1.009064 on the booked fee.
- enroll [`0x1234ebce..f8e824`](https://testnet.arcscan.app/tx/0x1234ebce93ce78b15a937fdadbfaa0e6f0ca47c45e6539d5312c0b2908f8e824) · deposit [`0x30a3d30d..7658cf`](https://testnet.arcscan.app/tx/0x30a3d30d36bd7bb6e5d036539e87f3e08b88a8ce6c5fe7d527f7d202337658cf) · advance [`0xa2411d96..4fb1b8`](https://testnet.arcscan.app/tx/0xa2411d96a41fcca1dd9075b619dfa53f91012ad2380b3a22eeb3dfe06b4fb1b8)

Every attestor run and settlement is logged with its hashes in [log.md](log.md).

## The determinism spine

The same policy engine exists three times, and all three must agree byte for byte:

| Implementation | Where | Role |
| --- | --- | --- |
| Solidity | [`contracts/src/PolicyEngine.sol`](contracts/src/PolicyEngine.sol) | Canonical: the verdict that moves funds |
| TypeScript | [`engine/`](engine/) | Recomputed in the browser on the public verifier |
| Swift | [`mobile/`](mobile/) | Recomputed on the buyer's phone |

Fourteen golden vectors (plus engine-generated hashes) are asserted by forge and vitest in the same commit whenever the engine changes. The [public verifier](https://recourse-arc.vercel.app/verify/13) runs the Solidity engine via eth_call and the TypeScript engine in your browser, then shows both verdict hashes matching. The pitch is literal: do not trust the verdict, recompute it.

The same trick binds commerce data. An order manifest (item, description, image hash, price) is an exact JSON document whose keccak256 IS the bytes32 orderRef the escrow stores. The buyer's phone refetches the bytes, rehashes them, and cross-checks every economic field against the QR before allowing payment. Product images are content-addressed the same way (and mirrored to a CDN, which changes delivery, not trust: the phone rehashes whatever bytes arrive). A cross-language golden fixture (`0xa4e970..a88b7cd`) is asserted in Rust, Swift, and TypeScript.

## The three-sided market

- **Buyers** (iOS app): a Secure Enclave device wallet, camera-scannable checkout QRs (universal links), verified order review before paying, Face ID-signed evidence upload, and receipts whose outcomes are recomputable.
- **Merchants** (iOS + [web workspace](https://recourse-arc.vercel.app)): publish immutable policies, generate checkout QRs with hash-bound order details, get paid instantly through the vault while the buyer keeps the full protection window.
- **Liquidity providers** ([vault](https://recourse-arc.vercel.app/vault)): deposit USDC, fund T+0 merchant advances, earn advance fees plus USYC float yield, and absorb refund losses that are bounded by immutable policies and per-merchant exposure caps. LP net return = advance fees + float yield - refund losses, and every term is inspectable onchain.

While escrowed, funds are never idle: the escrow deposits into a USYC-style yield adapter, and yield is split between the beneficiary and the protocol treasury at settlement.

## Architecture

```
contracts/   Solidity: escrow, policy engine + registry, settlement vault, yield adapter
engine/      TypeScript mirror of the engine (verifier parity, golden vectors)
packages/    Golden vectors shared by forge and vitest
mobile/      Native SwiftUI iOS app (buyer + merchant counter), no wallet SDK
web/         Next.js: landing, merchant workspace, vault, public verifier, /pay links
backend/     Rust (actix): indexer + read API + evidence/order stores. Holds no business logic
ops/         Deploy, codegen (addresses flow from deployments/ only), vault ops scripts
```

Trust boundaries are deliberate. The backend is a projection of chain state and a transport for content-addressed bytes; it cannot decide verdicts or alter orders without breaking a hash. The attestor can only assert narrow facts (delivered or not); what those facts mean is fixed by the policy forever. Auth for uploads is an EIP-712 signature proving the caller is the onchain buyer.

## Deployed on Arc testnet (chain 5042002)

| Contract | Address |
| --- | --- |
| RecourseEscrow | `0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0` |
| PolicyRegistry | `0x94f8551fbE43aB919D87c3951394b148c914430E` |
| SettlementVault | `0x5d8a3000866493f5D0B5B07a4Ad63ADE3B02054D` |
| Yield adapter (mock USYC) | `0x2336AaBE139b7F426aF63f713b9f93CD3FFC6204` |
| USDC (Circle, native) | `0x3600000000000000000000000000000000000000` |

## See it in five minutes

1. Open the [public verifier for payment 13](https://recourse-arc.vercel.app/verify/13): the refunded Fish payment. Watch the browser recompute the onchain verdict and match hashes.
2. Open [payment 15](https://recourse-arc.vercel.app/verify/15): the denied Wrong item claim. Same engine, opposite outcome, equally provable.
3. Browse the [vault](https://recourse-arc.vercel.app/vault): live TVL, share price, and the two outstanding T+0 advances with their settle dates.
4. Sign in on the [web workspace](https://recourse-arc.vercel.app/signin): every account gets a provisioned Arc wallet, and the dashboard reads only live chain and indexer state.

To run the full loop yourself (pay from a phone, dispute, watch settlement) build the iOS app: `cd mobile && ruby scripts/generate_project.rb && open Recourse.xcodeproj`. Tests: `forge test` (contracts), `npx vitest` (engine), `cargo test` (backend), and the iOS suite via Xcode.

## Honest limitations

This is a testnet prototype. The yield adapter mocks USYC until Teller access is approved; the demo attestor is a single key behind DEMO_MODE and admin auth (production is N-of-M attestations, and the design already caps what any attestor can do); the vault omits inflation-attack hardening; contracts are unaudited. The path to production is real precisely because the trust model was drawn first: everything the backend does is either reproducible from public state or breaks a hash.

---

Built solo for the Build on Arc hackathon (DeFi track). USDC through the ERC-20 interface at 6 decimals throughout. Session-by-session engineering record in [log.md](log.md).
