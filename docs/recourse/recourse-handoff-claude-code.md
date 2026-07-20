---
project: recourse
consumer: claude-code
version: 1.0.0
date: 2026-07-20
description: Full-context handoff for the Claude Code agent building Recourse, a buyer-protection and dispute-resolution layer for USDC on Arc, for the Build on Arc hackathon (final submission 2026-08-09).
companion-docs: recourse-prd.md, recourse-architecture.md
---

# Recourse: Handoff for Claude Code

---

## Level 0: Elevator Pitch

Read this layer if you have ten seconds.

Recourse is buyer protection for digital dollar payments. When someone pays a merchant, the money sits briefly in a protective holding account that earns interest, governed by a refund policy written as code. If something goes wrong, the dispute is decided automatically by that policy, and anyone can re-run the decision to check it. Merchants still get paid instantly because a pool of lenders fronts the money.

Stop here if you only needed to know what this is.

---

## Level 1: Executive Summary

Read this layer if you are deciding how much attention this project deserves.

Recourse exists because stablecoin payments behave like cash: once sent, there is no recourse, and that single missing property is a large part of why commerce still pays card networks 2 to 3 percent. Circle Research published a prototype called Refund Protocol in April 2025 and, unusually, also published the list of problems that kept it from becoming a product: arbiters with too much power, escrowed money earning nothing, gas costs, and merchant cash flow trapped in escrow. As of mid-2026, Arc (Circle's stablecoin-native Layer 1, mainnet expected this summer) makes every one of those problems solvable, and Recourse is the project that solves them, built for the Build on Arc hackathon's DeFi track with a final submission due Sunday, August 9, 2026.

The system has four parts. A protected checkout escrows each payment and pins it to a hashed, machine-readable refund policy. A deterministic policy engine decides disputes from evidence, producing verdicts that anyone can recompute in a browser. A yield adapter sweeps escrowed funds into USYC, Circle's tokenized Treasury fund, so protection pays for itself. And a settlement vault lets liquidity providers pay merchants at T+0 in exchange for the escrow claim, earning fees and float yield while underwriting dispute risk with computable bounds.

You, the consumer of this document, are the Claude Code agent that will scaffold and build the entire monorepo: Solidity contracts on Arc testnet, a TypeScript engine mirror, a thin Rust backend, a Next.js web surface, and a Flutter buyer app. Your product requirements live in recourse-prd.md and your technical blueprint lives in recourse-architecture.md; this document tells you how to work, in what order, and under which standing rules. The bar is a working prototype deployed on Arc, filmed in a three-minute video, judged on execution quality over complexity.

Stop here if you are a human triaging whether to open the other documents.

---

## Level 2: Product Overview

Read this layer if you will make product decisions during the build.

The tagline is "buyer protection for USDC," and the positioning is deliberate: Recourse is not a payments app, a lending fork, or an escrow dApp. It is the recourse layer that card networks bundle into their 2 to 3 percent, unbundled and repriced in basis points, running natively on the chain Circle built for stablecoin finance. The audience is three-sided. Buyers are ordinary people paying merchants who want to know, before paying, exactly what happens if the item never arrives. Merchants are online sellers who will not accept a payment method their support team cannot resolve disputes on, and who will revolt against anything that delays their payout. Liquidity providers are yield-seekers who want a cash flow with legible risk.

The consumer-facing flow, end to end: a merchant authors a refund policy in a visual builder (for example, "damaged item, photo within three days, full refund"), publishes it onchain where it becomes immutable, and shares a checkout link or QR code. A buyer scans the code in the Recourse mobile app, reads the policy card, and pays USDC. The funds escrow, sweep into yield, and, if the merchant enrolled in the vault, the merchant is paid instantly by the vault, which takes over the claim. If nothing goes wrong, the escrow releases after the dispute window and the claim holder collects principal plus yield. If something does go wrong, the buyer files a dispute from the app with photo evidence, an attestor bot confirms any objective facts like delivery status, and the contract itself computes the verdict from the policy. The verdict is a stamped outcome with a hash that a public verify page recomputes live, which is the demo's signature moment.

What Recourse is not matters as much. It is not a marketplace, not a wallet, not a fiat on-ramp, not a subscription or mandate system, not a multi-arbiter court, and not a mainnet product. It does not touch Arc's StableFX engine or confidential transfers. It has no token. Anything on that list that appears tempting mid-build is scope creep and should be declined; the PRD's section 8 is the canonical non-goals list.

Stop here if you will only work on copy, design, or the deck.

---

## Level 3: Brand and Vocabulary

Read this layer before writing any user-facing word or styling any screen.

The voice is confident, plain, and financial without being cold. Short declarative sentences. No crypto slang in user-facing surfaces: no "degen," no "ape," no "wagmi." Never use em dashes anywhere, in UI copy, docs, comments, or commit messages; use commas, colons, or parentheses. Amounts render in tabular monospace figures with the USDC suffix. The visual identity is light editorial in the house style: cream and off-white grounds, ink-dark text, a serif display face for headlines over a grotesk body, generous whitespace, minimal chrome. The product motif is the receipt and the ledger: perforated card edges, a physical stamp treatment for verdicts (REFUNDED, PARTIAL, DENIED) with a subtle stamp-down animation, one deep ledger-green accent, red reserved exclusively for the DENIED stamp. Every surface (app, dashboard, verify page, deck, video) uses the same palette and type, because consistency is the cheapest form of polish.

Canonical glossary, terms to use exactly as written:

| Term | Meaning |
|---|---|
| Protected checkout | A payment routed through the escrow with a policy pinned |
| Policy | The machine-readable refund rules, immutable once published |
| Policy card | The human-readable rendering of a policy shown before paying |
| Dispute window | The period after payment during which a dispute can be filed |
| Verdict | The engine's output: refund basis points, return requirement, rule id |
| Verdict hash | keccak256 over policy hash, payment id, inputs, and outputs |
| Attestor | The role that signs objective facts only; it never decides outcomes |
| Advance | The vault paying a merchant at T+0 and taking the claim |
| Float yield | USYC yield earned on escrowed funds |

Anti-patterns, in the imperative: do not call the attestor an arbiter or a judge, the entire pitch is that no one judges. Do not describe escrow as "locking" merchant funds; with the vault, merchant funds are never locked. Do not use dark fintech-terminal aesthetics anywhere. Do not invent new names for the four components; they are the escrow, the engine, the adapter, and the vault.

Stop here if you are only producing the deck or video script.

---

## Level 4: Working Spec: Claude Code Build Agent

Read this layer if you are the agent building the repository. This is the center of gravity of the document.

Your two companion documents divide the load. recourse-prd.md owns what to build and why: flows F1 through F7, the policy JSON schema, vault mechanics, the demo script, the rubric mapping, and the milestone calendar. recourse-architecture.md owns how: the monorepo tree, chain configuration, full contract interfaces, the engine parity discipline, backend routes and tables, web pages, mobile screens, and the dependency-true build order in its section 11. When this document and those documents disagree, the architecture document wins on technical shape, the PRD wins on product behavior, and this document wins on process.

Work in sessions, and open every session the same way: read handoff.md in the repo root (blockers at the top, then ordered next actions, then standing rules), then read the newest entries of log.md. Never re-decide something a past session already settled; if a settled decision seems wrong, log the objection and raise it rather than silently diverging. Close every session by appending to log.md (newest first: what was found, what was fixed, what rule the session earned), updating handoff.md, and committing. Commits are per session minimum, per meaningful unit ideally, always with working tests. The repo-root handoff.md is a rolling operational file and is distinct from this document; seed it in the first session from the standing rules below.

The standing rules, each of which exists because breaking it would sink the project. One: USDC flows through the ERC-20 interface at 6 decimals only; the native gas representation is 18 decimals and touching it for product logic corrupts every amount, so balances and transfers never read native. Two: the verdict engine exists exactly twice, canonical Solidity and the TypeScript mirror, chained together by the golden vectors in packages/vectors; any engine change updates the vectors and passes both forge and vitest suites in the same commit, and Rust and Dart never grow a third implementation, they call previewVerdict via eth_call or read the API. Three: contract addresses come only from deployments/arc-testnet.json through the codegen outputs; a hardcoded address anywhere is a bug. Four: the Rust backend contains no business logic, it indexes, stores evidence blobs, serves reads, and signs demo attestations, nothing else. Five: Flutter serves the buyer only; merchant and LP functionality lives on the web, and requests to add merchant screens to mobile are declined as scope creep. Six: demo-only endpoints are gated behind DEMO_MODE and labeled as such in code. Seven: testnet only; no script, config, or env file ever points at a mainnet RPC, and the four testnet private keys are throwaways that appear nowhere else in the owner's life. Eight: never run the seeder or attestor bot against a deployment mid-demo-rehearsal without logging it, because mystery state during rehearsal wastes hours.

Build in the order of architecture section 11, because it is dependency-true and front-loads the deterministic core: engine and vectors before escrow, escrow before vault, contracts deployed before backend, verify page before dashboard, dashboard before mobile, and the stretch gate (Gateway pay-in, EIP-3009 single-signature pay, the x402 agent-dispute demo for the Agentic track) opens on August 4 only if everything before it is done. The calendar in PRD section 12 maps this to the hackathon's checkpoints; the immovable dates are Checkpoint 2 on Sunday July 26 (public repo, deployed core contracts, a progress writeup, ideally a short clip of the verify page) and final submission by August 7, two days before the August 9 deadline, because the platform locks and late submissions are not judged.

Definitions of done, per phase. Contracts are done when forge tests pass including every golden vector, a deploy script writes deployments/arc-testnet.json, and a scripted end-to-end run on Arc testnet completes pay, dispute, attest, resolve, and release with correct USDC movements. The engine mirror is done when vitest passes the same vector file byte-for-byte on verdict hashes. The backend is done when the indexer replays the seeded history into Postgres from a cold start and every read route returns coherent JSON. The web is done when a stranger can open /verify/[paymentId] for a seeded dispute, watch the local recompute match the onchain hash, flip an input in the sandbox, and watch the verdict change. Mobile is done when the filmed path works on a physical device: scan, policy card, pay, receipt with yield ticker, dispute with camera, verdict stamp. The project is done when the three-minute video covering PRD section 9's beats exists, the deck exists in the same visual system, and the submission is in.

When you hit ambiguity the documents do not resolve, prefer the choice that strengthens the demo script's beats, then the choice that is simpler to defend under a judge's question, then the smaller diff. Log the choice either way.

Stop here if you are not also choosing toolchain details.

---

## Level 5: Technical Recommendations

Read this layer when setting up tooling or resolving stack-level choices.

Contracts use Foundry with solc 0.8.24 or later, forge-std for testing and stdJson for vector loading, and OpenZeppelin only for ReentrancyGuard, Ownable, and SafeERC20; everything else is small enough to write directly. The TypeScript engine lives in engine/ as a plain package with vitest, viem for hashing and ABI encoding so hashes match Solidity exactly, and no framework. The backend pins recent stable Rust with axum 0.7, tokio, sqlx with the postgres feature and compile-time checked queries where convenient, alloy for provider, bindings, and EIP-712 signing, and runs against the Postgres in ops/docker-compose. The web app is Next.js 14 App Router with wagmi v2, viem, and Tailwind, with the injected connector alone being acceptable for testnet. Mobile pins current stable Flutter with web3dart, riverpod, mobile_scanner, image_picker, flutter_secure_storage, and dio, and configuration arrives via dart-define. RPC endpoints and any additional Circle contract addresses (USYC Teller, Gateway) are read from docs.arc.io at build time by a human or fetched into deployments config, never guessed from memory. Useful references while building: the Arc docs contract addresses page for USDC decimals and Teller flow, the circlefin/arc-nanopayments repository if the agent-track stretch opens, and the Circle faucet for USDC and EURC on Arc testnet. The video is produced with Remotion, voiceover optional via ElevenLabs, and the deck reuses the web's design tokens.

Stop here unless you need the audit trail.

---

## Level 6: Source Material and Open Questions

Read this layer if you need to trace a claim or resolve something the documents left open.

This handoff was produced from the July 20, 2026 planning conversation in which the project was conceived, researched, and council-reviewed, together with live web research performed in that session. The load-bearing sources: Circle's Refund Protocol announcement and its published limitations (circle.com/blog/refund-protocol-non-custodial-dispute-resolution-for-stablecoin-payments); the Arc docs contract addresses page (docs.arc.io) for the USDC 6-versus-18 decimal split, the EURC address, and the USYC Teller flow; the Encode Club Programmable Money Hackathon pages for the rubric signals, tracks, and checkpoint dates; and Circle's Arc testnet launch and whitepaper coverage for the mainnet-summer-2026 timing. The PRD's rubric table paraphrases the hackathon's own "what we're looking for" list.

Deliberately excluded, so their absence is not mistaken for oversight: mainnet deployment and audits (out of hackathon scope, listed as roadmap), StableFX and confidential transfers (roadmap-fragile dependencies), risk-based vault pricing (flat 50 bps for MVP), EIP-1271 contract-wallet support, multi-arbiter governance, and every alternative project the council rejected (FX forwards, USYC intraday repo, confidential payroll), which live only in the originating conversation.

Open questions to resolve early, in priority order. First, USYC testnet access: apply immediately, and until approved the MockUSYCAdapter is the wired adapter; the swap is a redeploy. Second, whether Arc testnet USDC exposes EIP-3009 receiveWithAuthorization; verify onchain before building the single-signature pay stretch. Third, the exact current Arc testnet RPC endpoints, to be pulled from docs.arc.io into env config at setup. Fourth, resolveDelay pacing for the live demo, defaulting to 60 seconds until rehearsal proves otherwise. Fifth, at Checkpoint 2, scan the Encode project gallery for refund-adjacent entries and, if any exist, sharpen the framing around the deterministic engine and the vault, which are the two components no near-neighbor will have.
