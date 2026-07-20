# log.md (append-only, newest entries at the top)

Convention: every session appends one entry above this line's predecessors. Format: date, what was found, what was fixed or decided, what rule the session earned. Never edit or delete past entries.

---

## 2026-07-20: Session 0, project founding

Found: Circle Research published Refund Protocol (April 2025) with its open problems listed publicly; Arc testnet provides USYC via Teller, sub-cent USDC gas, and mainnet lands summer 2026. The hackathon rubric rewards a deployed prototype, Circle tool usage, path to production, and execution over complexity.

Decided: D1, project is Recourse, buyer protection for USDC on Arc (DeFi track). D2, four components: escrow, deterministic policy engine, USYC yield adapter, instant settlement vault. D3, stack fenced: Solidity canonical logic, TS engine mirror, thin Rust backend (index, evidence, attest), Next.js web, Flutter buyer-only mobile. D4, determinism spine: golden vectors shared by forge and vitest; Rust and Dart eth_call only. D5, addresses flow from deployments/arc-testnet.json via codegen only. D6, MockUSYCAdapter ships behind IYieldAdapter until Teller access approved. D7, stretch gate (Gateway pay-in, EIP-3009 pay, x402 agent dispute) opens Aug 4 only if core is done. D8, CP2 target Jul 26: deployed core contracts, public repo, verify-page clip.

Rules earned: R1, USDC through the ERC-20 interface (6 decimals) only, never native 18 for product logic. R2, engine changes ship with updated vectors and both suites green in one commit. R3, no em dashes in any copy, docs, or commits. R4, testnet keys are throwaways used nowhere else; no mainnet RPCs anywhere. R5, demo-only endpoints live behind DEMO_MODE.
