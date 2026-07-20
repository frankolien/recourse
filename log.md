# log.md (append-only, newest entries at the top)

Convention: every session appends one entry above this line's predecessors. Format: date, what was found, what was fixed or decided, what rule the session earned. Never edit or delete past entries.

---

## 2026-07-20: Session 4, deploy and codegen pipeline

Found: a real Arc deploy is blocked on the RPC and the real USDC address, but the deploy wiring (constructor args, setVault, buffer funding) and the address codegen can be written and fully verified locally without Arc.

Decided: D16, the deploy script picks its output filename by chainId: Arc (5042002) writes deployments/arc-testnet.json and requires RECOURSE_USDC; any other chain writes deployments/local-<chainId>.json, so a local dry-run can never clobber the canonical Arc address book. D17, generated address books (engine/src/addresses.ts) and local dry-run deployments (deployments/local-*.json) are gitignored; the real deployments/arc-testnet.json is committed after an Arc deploy as the address source of truth. D18, codegen is a small node script (ops/codegen.mjs) rather than Solidity, since it emits typed TS; it takes the deployment JSON path as an argument and is structured to add backend and mobile targets later.

Built: contracts/script/Deploy.s.sol (env-driven: RECOURSE_USDC, RECOURSE_ATTESTOR, RECOURSE_TREASURY, RECOURSE_YIELD_FEE_BPS, RECOURSE_RESOLVE_DELAY, RECOURSE_ADAPTER_BUFFER; deploys registry, adapter, escrow, vault, wires setVault, funds the mock buffer on the local path, and writes the address book). ops/codegen.mjs (emits engine/src/addresses.ts). Added ../deployments to fs_permissions. Verified end to end with a local in-memory dry-run: deploy wrote deployments/local-31337.json, codegen produced engine/src/addresses.ts, and tsc accepted it. Dry-run artifacts removed and gitignored.

Rules earned: none new.

---

## 2026-07-20: Session 3, M1 stateful contract layer (escrow, adapter, vault)

Found: three design points the docs left implicit. One, a simulated yield adapter has no external yield source, so redeem can only pay principal plus yield if the adapter holds a USDC buffer. Two, the doc says assign is callable by "the current beneficiary," but at advance time the beneficiary is the merchant while the caller is the vault, so that phrasing cannot implement T+0. Three, distributing exactly the redeemed total without dust needs one payout computed as the residual.

Decided: D12, MockUSYCAdapter pays yield from a pre-funded USDC buffer (deploy and tests fund it) and tracks per-caller shares so it cannot be drained by a stranger; the real Teller has its own source and the swap stays a redeploy. D13, the escrow stores a trusted owner-set vault address and assign is vault-only; the vault's advance pays the merchant net and checks enrollment and caps first, so the merchant is never harmed. This is a deliberate refinement of the doc's "only current beneficiary." D14, resolve and release pay the buyer refund and the treasury yield fee, then the beneficiary receives the residual, guaranteeing buyer + protocol + beneficiary == redeemed total with no dust. D15, the vault carries advances at par in totalAssets (idle + outstanding); reconcile decrements outstanding after settle so realized PnL flows into share price, with a documented transient between the escrow payout and reconcile.

Built: src/interfaces/IYieldAdapter.sol, src/MockUSYCAdapter.sol (linear 4.5% APY index, deterministic per timestamp). src/RecourseEscrow.sol (pay sweeps into adapter; fileDispute derives evidence mask and root; submitAttestation verifies an EIP-712 signature from the attestor with an s-malleability guard; resolve computes the verdict via PolicyEngine, redeems, splits funds, emits Resolved with the verdictHash; release for the happy path; assign vault-only; previewVerdict is the eth_call surface; getPayment for the vault and backend). src/SettlementVault.sol (minimal ERC-4626-shaped shares; deposit, withdraw bounded by idle, enrollMerchant owner-gated, advance pays T+0 and takes assignment, reconcile realizes PnL). Installed OpenZeppelin v5.1.0 as a pinned submodule (ReentrancyGuard, Ownable, SafeERC20, ERC20 for the test USDC only). test/mocks/TestUSDC.sol (6 decimals). test/EscrowVault.t.sol: 7 integration tests asserting exact USDC movement and conservation across happy-path release, attested full refund, un-attested resolveDelay deny, and the vault advance / reconcile profit and loss paths.

Green: forge 12 tests (5 core plus 7 integration), vitest 15 unchanged.

Rules earned: none new. Reinforced R1 (all product USDC through the 6-decimal ERC-20 interface) and the security posture in architecture section 10 (nonReentrant on all fund movers, checks-effects-interactions, exposure caps, resolveDelay guard).

---

## 2026-07-20: Session 2, M2 TS engine mirror and hash parity

Found: M0 left the vectors carrying only expected verdict fields, not hashes, so parity could only be asserted on the decoded verdict, not on the keccak256 outputs the verify page relies on. verdictHash also needs a paymentId, which the vectors lacked.

Decided: D10, the canonical policyHash and verdictHash per case are generated from the Solidity engine (the source of truth) into packages/vectors/hashes.json by a forge script (script/GenVectorHashes.s.sol), kept as a separate generated file so verdicts.json stays hand-authored. Both suites assert against it: forge as a regression lock, vitest as the parity check. D11, each vector carries an explicit paymentId; it is not derived from iteration index because forge parseJsonKeys order and JS Object.entries order are not guaranteed equal.

Built: added paymentId to all 14 vectors. Factored the forge vector reader into test/VectorReader.sol (inherits CommonBase, shared by the test and the generator script). GenVectorHashes script writes hashes.json; extended the forge suite to assert policyHash and verdictHash against it. engine/ TypeScript package: types.ts (mirror structs, timestamps as bigint), engine.ts (compute, identical branch logic to Solidity), abi.ts (viem ABI param defs in Solidity struct order), hash.ts (policyHash/verdictHash via viem encodeAbiParameters + keccak256; merchant lowercased to bypass viem checksum validation without changing the encoded bytes), index.ts. vitest loads the same two golden files, rebuilds the SoA rules, and asserts verdict fields plus both hashes byte-for-byte. Green: forge 5 tests, vitest 15 tests, tsc clean.

Rules earned: none new; reinforced R2 (engine changes ship with regenerated vectors/hashes and both suites green in one commit).

---

## 2026-07-20: Session 1, M0 deterministic core

Found: clean slate, only docs/ present, no git repo, no scaffold. Toolchain available: forge 1.7.1 (solc 0.8.28), node v25.8.2, cargo nightly; Flutter not needed until M4. Foundry's vm.parseJson decodes arrays of structs by alphabetical key order, a known gotcha that makes the naive vector schema fragile.

Decided: D9, golden vector schema is a top-level JSON object keyed by case name, with each policy's rules stored struct-of-arrays (one array per Rule field). Confirmed by a throwaway probe that vm.parseJsonKeys(json, "$") iterates cases, vm.parseJsonUintArray and vm.parseJsonBoolArray read the SoA fields (empty arrays included), and scalar-by-path reads work. This sidesteps the alphabetical array-of-structs decode gotcha and maps trivially to Object.entries in the TS mirror. This is a deliberate deviation from the illustrative array-of-objects format shown in architecture section 4; the semantics and the expect fields are unchanged.

Built: monorepo scaffold (contracts, engine, packages/vectors, backend, web, mobile, deployments, ops). Foundry project in contracts/. Types.sol (ClaimType enum, Rule, Policy, VerdictInput, Verdict; field order fixed for hash parity). PolicyEngine.sol (canonical pure library: first-match-wins, evidence bitmask subset check, attestation type-and-value match, inclusive [paidAt, paidAt + claimWindow] window, filedAt-before-paidAt guard, NO_RULE = 255 default). PolicyRegistry.sol (immutable, ids from 1, 16-rule bound, policyHash = keccak256(abi.encode(merchant, disputeWindow, defaultRefundBps, rules))). Golden vectors v1: 14 cases covering match, superset evidence, missing evidence, late window, boundary-inclusive window, attestation satisfied/failed/missing, first-match-wins, unknown claim type, filed-before-paid, and nonzero default. forge suite green: 14 vectors via one iterating test plus 4 registry tests (id increment, round-trip, hash formula, TooManyRules revert).

Rules earned: R10, comment with purpose only, never restate the code. R11, no GitHub push and no Co-Authored-By: Claude trailer in commits. R12, confirm the approach (research, subagents) before writing non-trivial code.

---

## 2026-07-20: Session 0, project founding

Found: Circle Research published Refund Protocol (April 2025) with its open problems listed publicly; Arc testnet provides USYC via Teller, sub-cent USDC gas, and mainnet lands summer 2026. The hackathon rubric rewards a deployed prototype, Circle tool usage, path to production, and execution over complexity.

Decided: D1, project is Recourse, buyer protection for USDC on Arc (DeFi track). D2, four components: escrow, deterministic policy engine, USYC yield adapter, instant settlement vault. D3, stack fenced: Solidity canonical logic, TS engine mirror, thin Rust backend (index, evidence, attest), Next.js web, Flutter buyer-only mobile. D4, determinism spine: golden vectors shared by forge and vitest; Rust and Dart eth_call only. D5, addresses flow from deployments/arc-testnet.json via codegen only. D6, MockUSYCAdapter ships behind IYieldAdapter until Teller access approved. D7, stretch gate (Gateway pay-in, EIP-3009 pay, x402 agent dispute) opens Aug 4 only if core is done. D8, CP2 target Jul 26: deployed core contracts, public repo, verify-page clip.

Rules earned: R1, USDC through the ERC-20 interface (6 decimals) only, never native 18 for product logic. R2, engine changes ship with updated vectors and both suites green in one commit. R3, no em dashes in any copy, docs, or commits. R4, testnet keys are throwaways used nowhere else; no mainnet RPCs anywhere. R5, demo-only endpoints live behind DEMO_MODE.
