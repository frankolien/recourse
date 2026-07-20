# log.md (append-only, newest entries at the top)

Convention: every session appends one entry above this line's predecessors. Format: date, what was found, what was fixed or decided, what rule the session earned. Never edit or delete past entries.

---

## 2026-07-20: Session 14, policy compiler and the visual policy builder

Found: the policy builder was the last big web piece, and it needed an engine compiler to turn authored JSON (PRD section 6) into the on-chain Rule structs. The risk was R2: the compiler must not become a third implementation of anything. The verdict logic lives in compute and the hash in policyHash, both already mirrored to Solidity.

Decided: make the compiler pure authoring and serialization. It maps claim-type and evidence and attestation names to the numeric struct fields, validates ranges (uint32 windows, bps 0 to 10000, at most 16 rules), and reuses policyHash and compute unchanged. The merchant is supplied separately because on-chain it is msg.sender, not part of the authored JSON. The builder previews only; publishing on-chain needs a wallet and is the next step.

Built: engine/src/compiler.ts (compilePolicy, toSpec, PolicyCompileError, name tables) exported from the package, with engine/test/compiler.test.ts (9 cases). The golden case authors the seed policy #1 spec and asserts it compiles to the exact structs and hash. Web: components/policy-builder.tsx and the /policies/new route, a two column authoring UI (policy settings, add and remove rules with claim type, evidence, attestation, window, refund, return) that live-compiles to the policy hash, shows the compiled Rule structs, tests a sample claim through compute, and copies the authored JSON. The /policies "New policy" button now routes here.

Verified: engine typecheck and 24 vitest cases green; web tsc, eslint, and the production build green (14 routes). The builder's default spec is policy #1, and its compiled hash rendered server-side as 0xc5a2b6c0d2ca...41fa892f, which is byte-for-byte the on-chain policyHash(1) read from Arc. Authoring JSON to TS compiler to Solidity registerPolicy all agree.

Rules earned: a compiler that sits next to a canonical engine earns its keep by reusing the engine's hash and compute, never by re-deriving them, and a golden test that ties the authored default to a live on-chain hash proves the whole chain in one assertion.

---

## 2026-07-20: Session 13, panel padding, Lottie accents, and a verifier dead end

Found: three issues surfaced while reviewing the new merchant routes. The base .dash-panel class had no padding (the dashboard's own panels each set their own via variant classes), so the new bare panels rendered flush to the border. The public verifier had no link back into the app: its logo and its "Public verifier" back link both pointed at /verify/5, the page itself, so they were no-ops and the page felt like a dead end. And the app used only static icons with no motion.

Decided: give the base .dash-panel a default 22px padding (the dashboard variants declare their own later and still override). Point the verifier logo and back link at /dashboard, relabel the back link "Back to app". Add Lottie for motion, but self-hosted and on-brand: use lottie-web directly (the MIT core has no React peer dep, so it installs against React 19 where the common React wrappers cap at 18), dynamic-imported inside a small client wrapper so it stays out of SSR and loads as a lazy chunk. Author the animation JSON by hand in brand green rather than pulling from a CDN, matching the offline, no-CDN posture used for fonts and seeding.

Built: components/lottie-player.tsx (dynamic import, reduced-motion aware, destroy on unmount), three hand-authored animations (loader, ping, burst) in lib/lottie, wired into the verify and policies loading states, the verify hash-match success (a ring burst behind the check), and the live indicators (the "Live on Arc" pill and the Arc Testnet chip on every merchant page).

Verified: production build is green (13 routes), tsc and eslint are clean, every route returns 200 with no SSR error from the JSON imports or the client player, and the verifier logo and back link resolve to /dashboard. lottie-web stays a lazy chunk, so First Load JS moved only 1 kB.

Rules earned: a control that looks like a back affordance must lead somewhere other than the current page, and a shared base class that expects per-variant padding will bite the next author who uses it bare, so give the base a sane default.

---

## 2026-07-20: Session 12, Geist typeface, real routing, and a full merchant app

Found: the dashboard was the only real merchant route. Its sidebar navigation mostly pointed at /verify/5 or dead # anchors, the shell was hard coded inside the dashboard component, and the app used Georgia and Inter rather than the requested xend.global typeface. xend.global was inspected directly and runs on Geist and Geist Mono (the Vercel typeface).

Decided: adopt Geist across the app through the self-hosted geist package (offline woff2, no CDN), keeping the design system intact by only swapping the three font tokens. Extract the sidebar and a persistent topbar into a shared MerchantShell driven by usePathname, mount it through a (merchant) route group layout so the sidebar persists across navigation and the active item and section title are always correct. Then give every navigation destination a real page instead of a redirect.

Built: MerchantShell (pathname active state, section title, persistent topbar, notification and profile links), a (merchant) route group, and eight routes: /payments, /protection, /disputes, /receipts, /vault, /policies, /settings, /support. The dashboard moved into the group and shed its embedded shell. Pages reuse the existing panel, table, and card vocabulary and add a small shared set (metric cards, records tables, status pills, address rows, toggles, how-steps). /policies reads policy #1 live from the registry and renders its rules and onchain hash. /vault and /settings surface the real contract addresses from deployments/arc-testnet.json with ArcScan links. The verifiable Arc payments (5 refunded, 6 denied) are linked from /payments, /receipts, and /disputes so the public proof is one click from the app.

Verified: production next build is green (13 routes), tsc --noEmit and eslint are clean, and every route returns 200 (root 307 to /dashboard). Confirmed the built CSS ships Geist @font-face with real woff2 files and defines --font-geist-sans, so the typeface loads rather than falling back. Confirmed server-rendered active nav and section title are correct on a sub-route, and that no href resolves to a dead anchor.

Rules earned: when a user asks for a specific site's font, inspect that site's stylesheet to identify it rather than guessing, and prefer the self-hosted package over a CDN so the app stays offline safe.

---

## 2026-07-20: Session 11, dashboard corrected to the supplied reference

Found: the first web delivery made the verifier the visual home, but the owner’s reference was the full account dashboard. The verifier was functionally correct but was the wrong primary surface and could not resemble the requested 1536 by 1024 dashboard screenshot.

Decided: keep the verifier as the public proof route, add the dashboard as its own surface, and redirect the root to /dashboard. Match the reference directly rather than stretching the verifier shell into a dashboard.

Built: /dashboard with the fixed buyer sidebar, account and network controls, USDC balance, protected payment and action summaries, monthly spend chart, active protection table, dispute timeline, recent activity, escrow earnings, learning cards, and support panel. Added responsive fallbacks for narrower screens while preserving the dense desktop composition.

Verified: rendered at the reference 1536 by 1024 viewport and visually compared against web.png. Content start, sidebar width, card grid, table density, dispute tracker, and right rail now align closely with the target. Browser console is clean. TypeScript and the production build are green; the unused import found by ESLint was removed.

Rules earned: when a user provides a target screenshot, the default route and information architecture are part of the visual requirement, not just the palette and component styling.

---

## 2026-07-20: Session 10, public verifier web experience

Found: web/ was still empty, while the seeded Arc deployment already exposed every read needed for the demo weapon through getPayment, getPolicy, policyHash, and previewVerdict. The seeded refunded and denied claims do not make evidence alone decisive, so a direct evidence toggle on the chain inputs would not demonstrate the promised outcome change.

Decided: build the verify surface before the dashboard, as required by the dependency order. The app reads Arc through dRPC in the browser, imports @recourse/engine rather than copying verdict logic, and sources contract addresses from deployments/arc-testnet.json. The sandbox includes an explicit local evidence-test preset that selects the damaged claim with no photo, then adding Photo changes the result from Denied to Refunded under Rule 2 without writing to chain.

Built: a Next.js App Router app in web/, public /verify/[paymentId] routes, responsive Recourse shell based on the supplied editorial dashboard reference, live payment and immutable policy panels, Solidity eth_call versus TypeScript hash comparison, refunded, partial, and denied stamp states, evidence sandbox, and demo links for payments 5 and 6.

Verified: npm build, TypeScript, and ESLint are green. Browser checks against live Arc confirmed payment 5 is Refunded 100 percent with matching hash 0x683e3c325e6e...bc650f, payment 6 is Denied with matching hash 0x87c2706fa4b2...421bb9, the evidence preset plus Photo changes the local result to Refunded under Rule 2, and the browser console has no warnings or errors.

Rules earned: none new. Reinforced R2 and R3 by importing the existing engine and deployment JSON directly.

---

## 2026-07-20: Session 9, demo state seeded and verified on Arc

Found: the public Arc RPC (rpc.testnet.arc.network) rate-limits hard and returns "request limit reached" as a JSON-RPC error that viem's transport does not retry, so the seed died on the first receipt poll across several attempts (each stranding a little USDC in a fresh funding address). Two other public endpoints answer without auth: dRPC (arc-testnet.drpc.org) and thirdweb (5042002.rpc.thirdweb.com).

Decided: D22, the seed wraps every RPC call in explicit backoff-retry that recognizes rate-limit and transient errors, reads counts once instead of per payment, and sleeps between txs; recommend running against dRPC rather than the official endpoint. D23, shrank seed amounts to 0.25 USDC per payment; the seed generates fresh (non-blocklisted) buyer and merchant keys on Arc and records their addresses in the pointer file.

Verified on Arc via dRPC: policyCount 1, paymentCount 8, payment 5 REFUNDED 100% (previewVerdict 10000/matched, status Settled, verdictBps 10000), payment 6 DENIED (previewVerdict 0, ruleIndex 255), payment 7 beneficiary == vault, vault.outstanding 0.25 USDC. Payment 5 settling a full refund without reverting confirms the underflow fix works on the live fixed contracts. Committed deployments/seed-arc-testnet.json (policyId 1, refund 5, deny 6, advanced 7).

Rules earned: none new.

---

## 2026-07-20: Session 8, redeploy with the fix and a viem seeder for Arc

Found: Arc's USDC is a native-token precompile (0x1800...0000). forge script executes run() locally to build its transaction list, and that local EVM cannot run the precompile, so any USDC movement reverts with StackUnderflow during forge's local execution. This is why the forge deploy worked (it moves no USDC) but the forge seed could not run on Arc, while cast send and the deploy's separate buffer transfer worked (they broadcast directly to the real node). The anvil dry-run hid it because local USDC is a plain ERC-20.

Decided: D21, the seeder is viem (direct RPC broadcast), not forge, so it runs on Arc; the forge Seed.s.sol was removed to avoid two seeders. Kept chain-aware funding (mint on local, deployer USDC transfer on Arc) and EIP-712 attestation via viem signTypedData against the same domain (RecourseAttestor / 1 / chainId / escrow). It lives in engine/scripts/seed.mjs to reuse the engine's viem dependency.

Built: engine/scripts/seed.mjs. Dry-ran end to end on anvil (deploy via forge, seed via viem): policyCount 1, paymentCount 8, payment 5 REFUNDED 100%, payment 6 DENIED, payment 7 beneficiary == vault, outstanding 1 USDC. Removed contracts/script/Seed.s.sol.

Redeployed the fixed contracts to Arc and verified on-chain: escrow 0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0, registry 0x94f8551fbE43aB919D87c3951394b148c914430E, vault 0x5d8a3000866493f5D0B5B07a4Ad63ADE3B02054D, adapter 0x2336AaBE139b7F426aF63f713b9f93CD3FFC6204. escrow.adapter/vault/usdc all correct; 10 USDC buffer at the new adapter; escrow bytecode grew (clamp) and adapter bytecode grew (ceil), confirming the fix is on-chain. Updated deployments/arc-testnet.json to the new addresses.

Then, running the viem seed on Arc, hit a second Arc-specific gotcha: Circle's USDC on Arc has a blocklist, and the well-known anvil merchant key (0x7099...79C8) is on it, so the deployer's USDC transfer to it reverted with "Blocked address". Fixed: on Arc the seed defaults the buyer and merchant to fresh random keys (generatePrivateKey), which are not blocklisted and are funded in-script; local dry-runs still use the anvil keys, which have ETH gas and no blocklist on the mock USDC. Also shrank amounts (0.25 USDC per payment) so re-runs are cheap, and the seed now records the merchant and buyer addresses in the pointer file.

Rules earned: none new (reinforces R13: the anvil dry-run and the Arc run exercise different USDC implementations; here Arc added both a native-precompile constraint and a blocklist that local testing cannot surface).

---

## 2026-07-20: Session 7, seed script and a settlement-underflow fix it caught

Found: writing the seed and dry-running it on a local anvil surfaced a real bug in the deployed contracts. MockUSYCAdapter floored shares on deposit and assets on redeem, so a deposit made when the index was already above 1.0, then redeemed after a short hold, returned a wei less than principal. In resolve() a full refund then computed toBeneficiary = total - refund - fee with total < refund and underflowed, reverting the settlement. On Arc this would brick any refund resolved soon after payment. Simulation hid it because forge runs all script txs at one timestamp (no index drift); only the real broadcast, with advancing block timestamps, triggered it.

Decided: D20, fix at the source and defensively. The adapter now rounds shares up on deposit so redeem never returns less than principal (guarantee: floor(ceil(a*W/i)*i/W) >= a); the extra wei is covered by the yield buffer. resolve() also clamps: refund is capped at total and the fee at the remainder, so a settlement can round a wei short but never reverts. Release was already safe.

Built: src/Seed.s.sol (multi-key via per-actor broadcast blocks; reads deployments/<network>.json; chain-aware funding: mint on local, deployer USDC transfer on Arc which also credits native gas; one policy, eight payments, two disputes attested to opposite verdicts, one vault advance; writes deployments/seed-<network>.json pointers). Fixed the adapter and escrow, added a regression test (test_resolve_fullRefund_shortHold_noUnderflow) that warps the index above 1.0 before paying and resolves immediately. Verified on anvil end to end: deploy, seed, then cast reads confirm policyCount 1, paymentCount 8, payment 5 REFUNDED 100% (verdictBps 10000, Settled), payment 6 DENIED (default, ruleIndex 255), payment 7 beneficiary == vault with outstanding 1 USDC.

Consequence: the first Arc deploy (commit ca3a5d2) has the buggy contracts and is now stale. Redeploy with the fix before seeding or demoing; handoff.md carries the runbook and a STALE marker.

Rules earned: R13, verify money-moving scripts against a real node (anvil), not just forge simulation; simulation runs at a single timestamp and hides time-dependent rounding.

Green: forge 13 tests, vitest 15 unchanged.

---

## 2026-07-20: Session 6, live deployment to Arc testnet

Found: the deploy went through cleanly. The forge broadcast console summary mislabels which address is which contract, so the authoritative sources are deployments/arc-testnet.json (written by the script) and on-chain reads.

Built and verified: deployed PolicyRegistry, MockUSYCAdapter, RecourseEscrow, and SettlementVault to Arc testnet (chainId 5042002), wired escrow.setVault, and funded the adapter with a 10 USDC yield buffer. Addresses: escrow 0x18BfF4cF4c0843EF17c0f12e7E5C940683e930a1, registry 0x4b1A69eBEbBb3aF4dD8741c78065DE3d271C1483, vault 0x2Fa3Aa1BD0cBb04B0e68Ca97bbf53Aa08e44a163, adapter 0x53678a5aeBeACeed4A6Efc3a5F9c22DcFF4d772D. Verified every wire on-chain with cast: escrow.usdc/registry/adapter/vault all correct, resolveDelay 60, yieldFeeBps 1000, attestor and treasury both the deployer 0xD6c574461d96Ee708f58Fe553049aD4f48BB983A, adapter.index just above 1e18, registry.policyCount 0, and 10 USDC sitting at the adapter. The buffer transfer target matched arc-testnet.json.yieldAdapter, confirming it landed on the real adapter despite the console mislabel. Total deploy cost about 0.10 USDC.

Committed deployments/arc-testnet.json as the address source of truth. engine/src/addresses.ts stays gitignored (regenerated by codegen). This clears the deployed-core-contracts core of Checkpoint 2.

Rules earned: none new. Note: the deploy was run by the user with their funded throwaway key; Claude verified the result on-chain but ran no broadcast (R11).

---

## 2026-07-20: Session 5, Arc testnet config pulled and verified

Found: the Arc testnet endpoints and Circle contract addresses, pulled from docs.arc.io (contract-addresses and connect-to-arc pages) rather than guessed, then verified live over the RPC. RPC https://rpc.testnet.arc.network returns chainId 5042002; USDC 0x3600...0000 reports 6 decimals and symbol USDC; the USYC Teller 0x9fdF14c5B14173D74C08Af27AebFf39240dC105A has bytecode. USDC and EURC addresses match what the architecture already documented.

Decided: D19, the immutable Circle-provided network facts live in deployments/arc-config.json (rpc, chainId, explorer, faucet, USDC/EURC/USYC, USYC Teller, CCTP, Gateway), with a source-and-verification note; secrets and per-deploy env live in .env.example (keys blank, never committed). This satisfies "pulled from docs.arc.io into config, never guessed."

Built: deployments/arc-config.json, .env.example, and a deploy runbook in handoff.md. Reframed the deploy blocker honestly: the endpoints are no longer the blocker; a live deploy now only needs a funded throwaway DEPLOYER_PK and a go-ahead to broadcast (an outward action not fired unilaterally). USYC access is still pending, so MockUSYCAdapter stays wired; the Teller adapter is a redeploy once approved.

Rules earned: none new. Reinforced the docs-over-memory rule for chain addresses.

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
