# handoff.md

Rolling operational file. Read this first every session: blockers, then next actions, then standing rules. The full spec lives in docs/recourse/. This file is distinct from the handoff doc; it is the live worklist.

## Live deployment (Arc testnet, chainId 5042002)

Fixed-contract deploy, verified on-chain 2026-07-20 (includes the settlement-underflow
fix). Addresses in deployments/arc-testnet.json; explorer https://testnet.arcscan.app/address/<addr>.

| Contract | Address |
|---|---|
| RecourseEscrow | 0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0 |
| PolicyRegistry | 0x94f8551fbE43aB919D87c3951394b148c914430E |
| SettlementVault | 0x5d8a3000866493f5D0B5B07a4Ad63ADE3B02054D |
| MockUSYCAdapter | 0x2336AaBE139b7F426aF63f713b9f93CD3FFC6204 |
| USDC (Circle) | 0x3600000000000000000000000000000000000000 |

(Superseded first deploy, kept for reference: escrow 0x18BfF4cF4c0843EF17c0f12e7E5C940683e930a1.)

Wiring verified: escrow points at usdc/registry/adapter/vault; resolveDelay 60, yieldFeeBps 1000;
attestor and treasury both set to the deployer 0xD6c574461d96Ee708f58Fe553049aD4f48BB983A;
adapter holds a 10 USDC yield buffer. To redeploy, re-run the deploy runbook below; a redeploy
means re-running codegen and re-committing arc-testnet.json.

## Blockers

1. USYC testnet access not yet requested. Apply via the Circle faucet/portal. Until approved, MockUSYCAdapter is the wired adapter; the swap to a USYCTellerAdapter (Teller at 0x9fdF14c5B14173D74C08Af27AebFf39240dC105A) is a redeploy. Not blocking anything else.
2. The demo attestor currently equals the deployer key. When the Rust attestor bot lands, either give it this key or rotate via escrow.setAttestor to the bot's address.

## Deploy + seed runbook

Redeploy (run from contracts/ for the forge step, repo root for the rest):
```
export ARC_RPC_URL=https://rpc.testnet.arc.network
export RECOURSE_USDC=0x3600000000000000000000000000000000000000
(cd contracts && forge script script/Deploy.s.sol:Deploy --rpc-url $ARC_RPC_URL --private-key $DEPLOYER_PK --broadcast)
cast send $RECOURSE_USDC "transfer(address,uint256)" $(node -e "console.log(require('./deployments/arc-testnet.json').yieldAdapter)") 10000000 --rpc-url $ARC_RPC_URL --private-key $DEPLOYER_PK
node ops/codegen.mjs
```
Then seed the demo state. The seeder is viem, not forge: Arc's USDC is a native-token
precompile that forge's local EVM cannot execute (StackUnderflow during simulation), so
seeding goes through direct RPC broadcast. Needs the deployer funded with ~10 USDC; it
funds the buyer and merchant in-script (small amounts, 0.25 USDC per payment). DEPLOYER_PK
is the attestor. On Arc the buyer and merchant default to fresh random keys because the
well-known anvil keys are on Arc USDC's blocklist; set SEED_BUYER_PK / SEED_MERCHANT_PK to
override.
```
node engine/scripts/seed.mjs        # defaults to deployments/arc-testnet.json
```
The seed writes deployments/seed-arc-testnet.json with the notable paymentIds (refund,
deny, advanced) for the verify-page demo. Dry-run verified end to end on local anvil
(deploy via forge, seed via viem). The forge seeder was removed for the reason above.

## Next actions (architecture section 11 order, dependency-true)

1. web/: the merchant app is now a full multi-page site. A shared MerchantShell (in components/) renders the sidebar and a persistent topbar with pathname-driven active state, mounted via the app/(merchant) route group layout. Real routes exist for /dashboard, /payments, /protection, /disputes, /receipts, /vault, /policies, /settings, /support; /policies reads policy #1 live from the registry; /vault and /settings show the deployed contract addresses with ArcScan links. The typeface is Geist and Geist Mono (xend.global's font), self-hosted via the geist package and wired through the --display/--body/--mono tokens. The public verifier remains at /verify/5 and /verify/6 with live Arc reads, browser recomputation, exact hash comparison, and an evidence sandbox. The visual policy builder is built at /policies/new: it authors rules, live-compiles to the policy hash via the engine compiler, shows the compiled structs, and tests a claim through compute. Remaining web work: publish a built policy on-chain (wallet connect, then registerPolicy from the merchant address, returning the new policyId), and turning the illustrative merchant data on the new pages into live indexer reads once the backend lands.
2. backend/ (Rust): indexer, then read routes, then evidence store, then attestor bot (architecture section 5). Reads addresses from deployments/arc-testnet.json via codegen.
3. engine/: DONE. The policy compiler (compilePolicy, toSpec, PolicyCompileError, name tables in engine/src/compiler.ts) turns authored JSON (PRD section 6) into Rule structs, reusing policyHash and compute (no third impl, R2). Covered by engine/test/compiler.test.ts, whose golden case ties the seed spec to the on-chain policyHash(1). The web policy builder at /policies/new authors rules, live-compiles to the policy hash, shows the compiled structs, and tests a claim through compute. Remaining: publish on-chain (wallet connect, then registerPolicy from the merchant address).
4. USYC access: apply; when approved, write USYCTellerAdapter and redeploy.

Demo state is seeded and verified on Arc (deployments/seed-arc-testnet.json): policyId 1,
8 payments, payment 5 REFUNDED 100%, payment 6 DENIED, payment 7 vault-advanced.
Re-seed by rerunning `node engine/scripts/seed.mjs` (produces a new policy + payments).

Done: deterministic core (M0), TS engine mirror with hash parity (M2), the stateful contract layer with integration tests (M1), the deploy + codegen pipeline, a live on-chain deployment to Arc testnet, the public verify page, and the dashboard overview. The dashboard matches the supplied 1536 by 1024 reference with the buyer sidebar, summary cards, protections, dispute tracker, activity rail, earnings, learning cards, and support panel. If the engine or vectors change, regenerate hashes.json (forge script script/GenVectorHashes.s.sol:GenVectorHashes) and keep forge and vitest green in one commit (R2).

## Standing rules

From the docs (each exists because breaking it sinks the project):

- R1. USDC flows through the ERC-20 interface at 6 decimals only. Never read native (18 decimal) balance for product logic.
- R2. The verdict engine exists exactly twice: canonical Solidity and the TS mirror, chained by packages/vectors. Any engine change updates the vectors and passes both forge and vitest in the same commit. No third implementation; Rust and Dart call previewVerdict or read the API.
- R3. Contract addresses come only from deployments/arc-testnet.json via codegen. A hardcoded address anywhere is a bug.
- R4. The Rust backend holds no business logic: index, store evidence, serve reads, sign demo attestations.
- R5. Flutter serves the buyer only. Merchant and LP live on the web.
- R6. Demo-only endpoints are gated behind DEMO_MODE and labeled as such in code.
- R7. Testnet only. No mainnet RPC in any script, config, or env. The testnet keys are throwaways used nowhere else.
- R8. Never run the seeder or attestor bot against a deployment mid-rehearsal without logging it.
- R9. No em dashes anywhere: UI copy, docs, comments, commit messages. Use commas, colons, or parentheses.

From the owner (this repo):

- R10. Comment with purpose only. A comment explains why (intent, a constraint, a gotcha, a spec reference), never restates what the code plainly does.
- R11. Do not push to GitHub. Commit locally only unless explicitly told to push. No Co-Authored-By: Claude trailer and no "Generated with Claude Code" line in commit messages.
- R12. Confirm the approach before writing non-trivial code: research the tradeoffs, check the pattern against the docs, and split work across subagents where it helps.
- R13. Verify money-moving scripts against a real node (anvil), not just forge simulation. Simulation runs every tx at one block timestamp and hides time-dependent behavior (yield-index drift, rounding); only a live broadcast with advancing timestamps exposes it.

## Session close checklist

Append to log.md (newest first: found, fixed or decided, rule earned), update this file, commit locally with a clean message.
