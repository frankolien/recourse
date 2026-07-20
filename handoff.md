# handoff.md

Rolling operational file. Read this first every session: blockers, then next actions, then standing rules. The full spec lives in docs/recourse/. This file is distinct from the handoff doc; it is the live worklist.

## Blockers

1. USYC testnet access not yet requested. Apply on day one via the Circle faucet/portal. Until approved, MockUSYCAdapter is the wired adapter and the swap to USYCTellerAdapter is a redeploy. Not blocking the deterministic core.
2. Arc testnet RPC endpoint, explorer, and USYC Teller address not yet pulled from docs.arc.io. Not blocking the engine (pure, chain-independent), but blocks deploy. Pull into env and deployments config before M1 deploy, never guess.

## Next actions (architecture section 11 order, dependency-true)

1. contracts/: deploy script (Deploy.s.sol) that deploys registry, adapter, escrow, vault, wires escrow.setVault, funds the adapter yield buffer, and writes deployments/arc-testnet.json. Then codegen (ops/) emitting engine/src/addresses.ts (and backend/mobile targets as those land). Blocked on the Arc RPC + real USDC address from docs.arc.io for a real deploy; the script can be written and dry-run locally first.
2. ops/: seed script (2 merchants, 8 payments, 2 disputes with opposite verdicts, 1 advanced by the vault) once deployed.
3. engine/: the policy compiler (authoring JSON, per PRD section 6, into Rule structs). compute and the hash utils already exist; the compiler is what the web policy builder and its live preview need. Not yet built.
4. Pull Arc testnet RPC and USYC Teller address from docs.arc.io into env and deployments config. Apply for USYC access.

Done: deterministic core (M0), TS engine mirror with hash parity (M2), and the stateful contract layer (RecourseEscrow, MockUSYCAdapter, SettlementVault) with integration tests green: pay, release with yield, dispute + attest + resolve, un-attested resolveDelay deny, and the vault advance / reconcile profit and full-refund loss paths, all asserting exact USDC conservation. If the engine or vectors change, regenerate hashes.json (forge script script/GenVectorHashes.s.sol:GenVectorHashes) and keep forge and vitest green in one commit (R2).

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

## Session close checklist

Append to log.md (newest first: found, fixed or decided, rule earned), update this file, commit locally with a clean message.
