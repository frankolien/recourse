# log.md (append-only, newest entries at the top)

Convention: every session appends one entry above this line's predecessors. Format: date, what was found, what was fixed or decided, what rule the session earned. Never edit or delete past entries.

---

## 2026-07-21: Session 33, wrong-wallet auth test and the automated settlement worker

Found: two follow-ups after the auth work. One, the unit tests prove signature recovery but never exercise the recovered != payment.buyer branch (a valid signature from the wrong wallet). Two, Codex asked to convert the attestor from manual demo-gated curls into an internal automated service, and to defer profile/session auth. Corrected an overstatement from Session 32: the golden viem test proves backend and JS agree, but the iOS client does not yet sign this (the Swift signer signs transactions, not arbitrary EIP-712), so mobile/ still has to implement the request-challenge, body-hash, EIP-712 Authorization signing, and X-Recourse-Auth encoding.

Built: engine/scripts/auth-negative-test.mjs, a focused negative integration test. A throwaway key signs a structurally valid EIP-712 authorization (the signature recovers to walletAddress) for a payment it does not own; the backend must 403, persist nothing, and not consume the nonce. jobs/resolver.rs, an automated settlement worker: is_resolvable mirrors the escrow's resolve() precondition exactly (status == Disputed && (attType != 0 || now >= filedAt + resolveDelay), read verbatim from RecourseEscrow.sol:197-200), readiness is re-confirmed against the live chain per candidate so a stale projection cannot double-settle, and it never decides the verdict (resolve() runs the onchain PolicyEngine, R2/R4). It is opt-in via ATTESTOR_AUTO_RESOLVE (off by default so it never surprise-settles a rehearsal), needs the attestor's funded wallet, and logs every settlement (R8). chain.resolve_delay() reads the delay once at startup; main spawns the worker when the attestor is enabled and the flag is set.

Verified: cargo test 9 pass (added the readiness test). The wrong-wallet test ran live against payment 11: wrong-wallet upload and manifest both 403, the blob was not stored (404), the real manifest was not overwritten, and Postgres confirmed both nonces stayed consumed=false (the 403 fires at the buyer check, before the atomic consume). The worker ran live on Arc: with ATTESTOR_AUTO_RESOLVE on, disputed paymentId 12 was attested and the worker settled it on its own about 7 seconds later (tx 0xbd5d83bb..4e13) to status Settled, verdict 10000 bps, with no manual resolve call.

Rules earned: test the authorization branch, not just signature recovery: a valid signature from the wrong signer is the real attack, and it must reject, persist nothing, and not burn the challenge. When automating a money-moving action, mirror the contract's own precondition exactly, confirm readiness against the live chain before sending, keep it discretion-free (the chain computes the outcome), make it opt-in so it never fires during a rehearsal, and log every action.

---

## 2026-07-21: Session 32, wallet-signature auth, admin-gated demo routes, buyer reads

Found: a mobile-facing review flagged the backend as a strong hackathon build but not production-safe. Real gaps: DEMO_MODE plus a set attestor key meant anyone reaching POST /api/demo/resolve could trigger settlement; the mobile app could only filter payments by merchant, not buyer; no pagination; the attestor self-check logged a warning but still enabled a broken writer; evidence accepted paymentId 0 (a zeroed getPayment record) and could validate an empty manifest; cargo fmt --check was failing. The owner relayed Codex's design call: wallet signature (EIP-712) with stored one-time challenges, separating buyer routes from privileged attestor routes.

Decided (with Codex): two auth boundaries matched to who is really acting. Buyer writes (evidence upload, manifest) use a wallet EIP-712 signature; there is no account, the caller proves they are the payment's on-chain buyer by signing. Admin routes (demo attest/resolve) use a shared bearer token, fail closed, and are never shipped to the mobile app (which resolves directly on Arc). Reads stay public because payment state is public chain data.

Built: services/auth with the EIP-712 Authorization message (string action, uint256 paymentId, address walletAddress, uint256 chainId, bytes32 bodyHash, bytes32 nonce, uint256 expiresAt), domain {name Recourse, version 1, chainId}. POST /api/auth/challenge issues a random single-use nonce (Postgres auth_challenges, 5 min TTL, pruned on issue). verify_buyer recovers the signer, checks action/chainId/expiry/bodyHash, requires the signer to equal getPayment(paymentId).buyer on the live chain, and consumes the nonce with an atomic UPDATE ... WHERE consumed=FALSE RETURNING so a captured signature is good for exactly one write. Evidence upload and manifest POST now require a base64 X-Recourse-Auth header carrying the signed envelope; the manifest body is read as raw bytes so bodyHash binds the exact JSON. demo/attest and demo/resolve now require Authorization: Bearer ADMIN_API_KEY (constant-time compared) and 503 when unset. GET /api/payments gained ?buyer= (with idx_payments_buyer) and both lists page with ?limit= (default 100, max 500) and ?offset=. Fixed: reject nonexistent payments (policyId==0) on evidence read and in auth; the attestor now disables itself on a failed self-check; cargo fmt across the crate. open-dispute.mjs signs the EIP-712 envelope for upload and manifest and prints the admin-bearer attest/resolve commands.

Verified: golden EIP-712 digest cross-checked against viem hashTypedData (cargo test, 8 pass) so the backend and the viem client (web, and the open-dispute reference) recover the same signer byte-for-byte. The iOS client does not yet sign this: the Swift signer currently signs transactions, not arbitrary EIP-712 authorizations, so mobile/ must still implement request-challenge, body hashing, EIP-712 Authorization signing, and the X-Recourse-Auth encoding against this same spec. Live on Arc: buyer-signed uploads for paymentId 11 (evidenceRoot 0x7a58d95173866ff77a7fab8c9ccdf7a99ff413d8ca6c374d0a270f9686fcfd71), manifest VERIFIED, settled via the admin routes; unauthorized upload, manifest, and resolve (missing and wrong credentials) and the zero paymentId were all rejected; ?buyer= returned only that buyer's payment and ?limit/?offset paged cleanly.

Rules earned: authorize an action by who is really performing it. A buyer proves control of their address with a signature (no shared secret in the app); an operator uses a bearer token; do not conflate the two. Privileged, fund-moving routes fail closed. A one-time nonce is only replay-safe if it is consumed atomically at verify time, and a captured signature must bind the exact request body it authorizes.

---

## 2026-07-21: Session 31, evidence manifest verification and browser-side fold

Found: the escrow stores only the folded evidenceRoot; the ordered (evType, hash) evidence list is fileDispute calldata, never state, so the list itself has to live off-chain. No off-chain reimplementation of that fold existed yet. Read the contract verbatim: fileDispute folds root = keccak256(abi.encodePacked(root, evType, hash)) left to right from bytes32(0), evType packed as one byte, so each preimage is exactly 65 bytes and the order is significant.

Built: backend compute_evidence_root (the fold) plus a deployment-scoped manifest store (keyed by chainId_escrow, because paymentIds restart at 1 on a fresh escrow while blobs stay content-addressed and unscoped). POST /api/evidence/manifest recomputes the fold and reads the payment's evidenceRoot straight from the escrow (ChainClient injected as web::Data), persisting the list only on an exact match and returning 422 otherwise, so there is no indexer lag in the trust path. GET /api/payments/{id}/evidence re-folds the stored list and re-checks it against the live chain on every read, catching a manifest tampered on disk. Extended open-dispute.mjs to upload evidence, cross-check each keccak locally, pin the items in fileDispute, then post the manifest. Web: lib/evidence.ts recomputes the same fold with viem encodePacked, and the verifier shows an evidence proof panel that re-folds the backend's list in-browser against the evidenceRoot it read from Arc itself (a lying backend just yields a red mismatch). Added /verify/10 as a demo case.

Verified: golden fold cross-checked against cast keccak vectors (cargo test, 6 pass). Ran the whole chain live on Arc (R8, R13): open-dispute opened paymentId 10 with a photo and a description, evidenceRoot 0x5f2c0b10a51d62aa96015f5f43c811facd535cd25bbfb32c796e78f2290d22ab, manifest VERIFIED; the served blob rehashes to its pinned hash; attested value 2 NOT_DELIVERED (tx 0x5a73b1e1401bdebe11580cf40afa5a7ac59a21a0fbb62972f493d65daaae461c) and resolved (tx 0xbe96e08eadd0addba55f7caf0368ed065e543ba8babf70847a48cd3bf02f84ab), leaving previewVerdict (10000, false, 0, true) and status Settled. The viem fold reproduces the same root, so Solidity, Rust, and TypeScript all agree on the evidenceRoot.

Rules earned: for a trustless view, the client recomputes the result itself and trusts the service only for raw inputs it can re-verify (the evidence item list), never for the verdict of the check. Verify against the live chain, not the projection, wherever the projection would insert indexer lag into a trust boundary.

---

## 2026-07-21: Session 30, biometric signing boundary and real Swift anvil lifecycle

Found: the local signer decrypted its Keychain credentials whenever `sign` was called, so the transaction boundary still lacked explicit device-owner consent. The safest UI-independent seam is a signer-owned authorization capability that runs before credential loading. LocalAuthentication's device-owner policy uses Face ID or Touch ID where available and permits the device passcode fallback required by the architecture. The first anvil harness attempts also exposed a validation trap: a successful `xcodebuild` can mean an opt-in XCTest skipped because shell variables were not forwarded to the simulator test host. Result bundles, not process exit alone, are the proof.

Built: added `TransactionAuthorizing` and `DeviceOwnerTransactionAuthorizer`, mapping unavailable, cancelled, and denied outcomes into typed errors. `TestnetLocalSigner` now requires authorization before loading its encrypted keystore password for every signature. Tests inject explicit allowing or denying authorizers; the denial test records secure-store loads and proves they do not increase after authorization fails. Added `ArcLocalWriteTests` plus `mobile/scripts/verify_local_writes.sh`. The harness resolves a simulator UDID, launches disposable anvil, deploys with the existing Foundry script, seeds with the existing viem path, temporarily injects local configuration into the generated test scheme, runs the real Swift gateway, and restores the clean deterministic scheme on exit.

Verified: the offline iPhone 16 Pro suite reports 29 passed, 2 intentionally skipped integration tests, and 0 failed. The opt-in local lifecycle result bundle reports 1 passed, 0 skipped, and 0 failed. That executed test signs and broadcasts approve, pay, fileDispute, and resolve through `TestnetLocalSigner`, `ArcContractWriter`, and `HTTPArcRPCTransport`; waits for every receipt; reconciles Paid, Disputed, and Settled records through `ArcContractReader`; checks the Solidity preview verdict; and proves the buyer's USDC balance is restored after the 100% refund. No Arc transaction was broadcast.

Rules earned: authorization belongs inside the signer boundary, before secret loading, not in a future SwiftUI button that another caller could bypass. For opt-in integration tests, verify the result bundle says passed rather than accepting exit code zero, because XCTest skips are successful processes. Money-moving native adapters need one reproducible real-node lifecycle that uses the same signer, transport, ABI, and reader as the app.

---

## 2026-07-21: Session 29, testnet signer and complete Swift write gateway

Found: the existing workflow protocols already defined the correct write boundary, but the native app still lacked account custody, transaction construction, raw submission, and receipt reconciliation. web3swift 3.3.2 can create and serialize an encrypted Ethereum V3 keystore and sign legacy EIP-155 transactions without leaking third-party objects across actor boundaries. The deployed escrow write surface needed only approve, pay, fileDispute, and resolve. A receipt topic conversion also needed an explicit throwing initializer so untrusted RPC hashes could not select the trusted construction path.

Built: added a testnet-only `TestnetLocalSigner` that stores the encrypted keystore and a random password as separate `WhenUnlockedThisDeviceOnly` Keychain records. Added typed unsigned transactions, logs, receipts, transaction transport, and polling clock boundaries. Extended `HTTPArcRPCTransport` with pending nonce lookup, gas estimation plus margin, gas price lookup, raw transaction submission, and receipt decoding. Added `ArcContractWriter` for exact reviewed ABI calldata, local signing, 90-second receipt polling, and Paid event payment ID extraction. Added `ArcContractGateway` to compose reads and writes behind the existing business workflows. Expanded the source-controlled ABI fixtures and kept them exactly aligned with the corresponding Foundry functions.

Verified: exact calldata fixtures cover approve, pay, fileDispute, and resolve. Signer tests cover account persistence, deterministic signing, and reset through an in-memory secure store. Writer tests cover destination selection, signed raw submission, receipt polling, Paid event extraction, and timeout. ABI parity and deterministic Xcode regeneration pass. The complete offline iOS suite reports 28 passed, 1 intentionally skipped live test, and 0 failed, with no live transaction broadcast.

Rules earned: a successful transaction hash is not a business result. Native writes wait for a receipt and workflows still reconcile authoritative contract state. Treat every RPC hash as untrusted input even inside receipt decoding. The current Keychain accessibility protects data at rest and while locked, but it is not a Face ID transaction-confirmation boundary; add LocalAuthentication before UI binding and verify the full money-moving lifecycle against anvil per R13.

---

## 2026-07-21: Session 28, restructure the Rust backend into layered modules

Found: the owner reviewed the backend against their qent codebase (rust_projects/qent) and was not a fan of the flat layout (all handlers in routes.rs, models mixed into db.rs and chain.rs, main.rs doing everything, one AppState god-struct).

Studied qent's conventions: handlers/ (one file per resource), services/ (integrations plus AppConfig), models/ (glob-re-exported data types), jobs/ (background), an app.rs::build_app split from a thin main.rs, dependency injection as separate web::Data<T> per thing (including web::Data<Option<T>> for optional services), queries inline in handlers, and sqlx::migrate! for schema.

Built: restructured backend/src to match. app.rs owns CORS plus the route table; handlers/{health,payments,disputes,policies,evidence,demo}.rs; services/{chain,attestor,evidence}.rs plus services/mod.rs (AppConfig, renamed from Config); models/{payment,policy}.rs; jobs/indexer.rs (the poller plus upserts plus reset_if_deployment_changed). Deleted the flat config.rs, chain.rs, db.rs, indexer.rs, routes.rs, attestor.rs, evidence.rs. Read queries moved inline into handlers; the AppState struct is gone in favor of per-dependency web::Data; sqlx::migrate!(./migrations) replaced the raw_sql bootstrap (added the sqlx migrate feature). Kept tracing rather than switching to env_logger.

Verified: byte-identical behavior. cargo build, cargo test (4 pass), and clippy --all-targets are clean. Ran live: sqlx::migrate! ran cleanly against the existing DB, the attestor enabled with digest verified, the indexer logged "indexed 9 payments, 1 policies" under jobs::indexer, /health and /api/payments returned 9, and the evidence roundtrip worked.

Rules earned: match the owner's established codebase conventions (layered handlers/services/models/jobs, per-dependency web::Data, app.rs split from main, sqlx::migrate!) instead of a flat ad-hoc layout. A pure structural refactor must prove byte-identical behavior by re-running the live path, not merely by compiling.

---

## 2026-07-21: Session 27, reviewed Swift ABI boundary and live Arc reads

Found: web3swift 3.3.2 exposes the needed ABI V2 support, but its higher-level contract call API returns non-Sendable dictionaries across an async boundary. Under Swift 6 strict concurrency, the safer boundary is to keep Web3Core's synchronous ABI encoder and decoder inside one actor and send only Data through a small JSON-RPC transport. The deployed mobile read surface is only seven calls. Policy and payment outputs include ordered Solidity tuples, and web3swift decodes those tuples as ordered Swift arrays.

Decided: pin web3swift exactly at 3.3.2 and check in Package.resolved. Keep minimal reviewed ABI JSON resources in the app bundle rather than relying on ignored Foundry artifacts at build time. Split ContractReading and ContractWriting while retaining ContractGateway as their composition. ArcContractReader owns all ABI objects and domain decoding. HTTPArcRPCTransport owns typed eth_call networking. Feature workflows see only Sendable domain records. The RPC URL is generated from deployments/arc-config.json, while every contract address still comes from deployments/arc-testnet.json (R3).

Built: IERC20, PolicyRegistry, and RecourseEscrow ABI fixtures containing only balanceOf, allowance, getPolicy, policyHash, getPayment, previewVerdict, and resolveDelay. Added deterministic Xcode resource wiring, exact Swift package wiring, and preservation of Package.resolved across project regeneration. Implemented live USDC balance and allowance reads, policy plus policy hash reads, payment decoding, previewVerdict decoding, and resolveDelay. Added typed RPC errors, integer overflow guards, enum validation, bytes32 validation, and nil claim handling for undisputed payments. Added raw call and response fixtures captured from seeded Arc state, selector and deployment-address assertions, ABI surface tests, and an opt-in live integration test.

Verified: project regeneration remains byte-identical and preserves Package.resolved. Four focused ABI and reader tests pass. The opt-in integration test passed against Arc testnet through dRPC, reading policy 1, settled payment 5, its 10000 BPS matched verdict, and resolveDelay 60. The complete offline iPhone 16 Pro suite reports 22 passed, 1 skipped, and 0 failed. The skipped case is the intentionally opt-in network test. The initial build exposed critically low disk space, so only regenerable Xcode, Flutter Runner, and SwiftPM caches were removed before validation.

Rules earned: keep third-party EVM objects and Any-based ABI values inside the gateway actor. Cross actor boundaries carry only Data or typed Sendable domain values. Store minimal ABI fixtures in source control and prove them with exact selectors plus raw node responses. Keep live RPC tests opt-in so the normal suite is deterministic and rate-limit independent.

---

## 2026-07-21: Session 26, iPhone buyer business logic before UI wiring

Found: the owner correctly challenged the order of work. The first native slice proved the project, generated config, exact USDC type, QR boundary, and visual shell, but feature UI should not advance until buyer workflows are explicit and tested. Mobile business logic must mean orchestration and client-side invariants only. Refund eligibility remains solely in Solidity plus the TypeScript verification mirror (R2).

Built: chain-aligned domain models for PaymentStatus, ClaimType, EvidenceKind, PolicyRecord, PaymentRecord, UploadedEvidence, VerdictPreview, and validated ChainHash. Refactored PaymentRequest to use a real bytes32 value instead of an unchecked string. Added Sendable infrastructure protocols: ContractGateway for reads, writes, receipt waiting, and previewVerdict; EvidenceRepository for offchain uploads; BuyerPaymentRepository for indexed lists; and UnixTimeProvider for deterministic boundary tests. Added three UI-independent workflows. CheckoutPlanner and CheckoutWorkflow validate deployment and merchant, check exact ERC-20 balance and allowance, branch between direct pay and approve-then-pay, stop on a reverted receipt, require a Paid event payment id, and reconcile buyer, merchant, policy, amount, and status from chain. DisputeWorkflow requires the recorded buyer and Paid state, uses the contract's inclusive paidAt plus disputeWindow boundary, uploads evidence in stable order, files, and reconciles Disputed state and claim type. VerdictWorkflow reads previewVerdict from the gateway, never computes rules, models attestation versus resolveDelay readiness, submits permissionless resolve, and requires Settled state before success. Refund display arithmetic uses quotient and remainder basis-point math to avoid multiplication overflow.

Verified: added actor-based gateway and evidence fakes plus checkout, dispute, and verdict suites. Swift 6 strict-concurrency build and all 18 tests pass on iPhone 16 Pro. Coverage includes direct pay versus approval, insufficient balance, approval revert stopping payment, onchain payment reconciliation, buyer authorization, closed-window rejection before upload, exact-boundary dispute acceptance, immediate readiness after attestation, resolve-delay waiting, settled-state confirmation, and chain-returned verdict use.

Rules earned: build mobile feature logic as deterministic workflows over protocols before view models. Mirror contract preconditions that protect UX, but never mirror the policy engine. Every transaction workflow ends by reading authoritative chain state rather than trusting submission success. Keep evidence order stable because the contract's evidence root is order-sensitive.

---

## 2026-07-21: Session 25, native iPhone M4.1 foundation

Found: mobile/ was empty, while Xcode 26.4.1, Swift 6.3.1, and the xcodeproj Ruby gem were available. No project generator CLI was installed. The first native slice needed to establish trustworthy money and QR types before pulling in an EVM dependency. Xcode macro plugins and Simulator services also require execution outside the filesystem sandbox, and the machine has very little free disk, so validation used an active-architecture simulator build and temporary DerivedData.

Built: a deterministic generated Xcode project at mobile/Recourse.xcodeproj with an iOS 17 SwiftUI application, Swift 6 strict concurrency, a shared scheme, camera and Face ID usage descriptions, and an XCTest target. The checked-in mobile/scripts/generate_project.rb produces byte-identical project files and puts deployment codegen before Swift compilation. Extended ops/codegen.mjs to emit mobile/Recourse/Generated/Deployment.swift from the canonical Arc deployment, kept ignored as generated output (R3), and documented the build in mobile/README.md. Added the feature-first app foundation: observable environment and typed router; Home, Scan, Receipts, and Account shells; editorial ledger-green design tokens; exact integer-only USDCAmount; validated EthereumAddress; versioned base64url PaymentRequest decoding with chain, escrow, amount, and bytes32 order-reference checks; and an actor-based KeychainStore. No EVM dependency or fake signer was added.

Verified: the project builds successfully under Swift 6 for the iOS Simulator. Seven XCTest cases pass on iPhone 16 Pro, covering six-decimal USDC parsing and formatting plus valid QR decoding and wrong-chain and wrong-escrow rejection. Launched the built app in Simulator and inspected a 402x874 screenshot: the serif editorial hierarchy, green balance card, scan action, tab bar, and account entry render without clipping. Project regeneration was run twice and produced no diff.

Rules earned: encode money as base-unit integers at the domain boundary, not Decimal or Double in feature code. Validate untrusted QR requests before navigation or network work. A generated Xcode project is only useful if regeneration is byte-stable, so pin otherwise-random dependency object IDs. Add the EVM library only behind the reviewed gateway and signer protocols, after the native shell and invariants are green.

---

## 2026-07-21: Session 25, full attestor loop verified live on Arc

Found: the attestor bot was built and unit-verified but never exercised end to end against a live disputed payment (the seeded 5/6 are settled). Needed a fresh Disputed payment, which is a buyer action (fileDispute must be signed by the payment's buyer, and the seeder's buyer key is a fresh random key that is not persisted).

Built: engine/scripts/open-dispute.mjs, a buyer-side helper that funds a fresh buyer, pays once, and files a dispute, then stops (no attestation), leaving the payment Disputed for the attestor. Reuses the seeder's viem patterns; defaults to dRPC on Arc.

Verified LIVE on Arc: opened paymentId 9 (buyer 0x11b8FB49...6Cf2Fe, policy 1, claimType 0). Before attestation it previewed DENIED (no rule matches without the delivery attestation, so the policy falls through to the 0% default). Ran POST /api/demo/attest {9, value 2 NOT_DELIVERED} (submitAttestation tx 0xa040...9735, accepted onchain, the first live proof the Rust signature recovers to the attestor), then POST /api/demo/resolve {9} (settlement tx 0x79da...dba0). previewVerdict(9) flipped to (10000, false, 0, true) = Refunded 100% matched; the indexer reflected status Settled refundBps 10000; chain verdictHash 0x5d05b6...f2867 equals the indexed hash. The full thesis ran: buyer disputes, attestor signs one objective fact, the immutable policy flips the verdict deterministically, anyone recomputes it.

Decided (owner directive): build the product fully real, no DEMO_MODE shortcuts, quality over the demo deadline. Codex owns the native iOS buyer app; this workstream owns the rest (evidence store, real auth, attestor-as-service, USYC swap). Real-build order: evidence blob store, then real auth (Circle Programmable Wallets), then un-gate the attestor into a real service; apply for USYC testnet access in parallel (lead-time gated). The one irreducibly external node is delivery truth (no real shipment on testnet); everything around it is fully real.

Rules earned: prove a cross-service loop on the real chain before trusting it, not just in unit tests. An un-attested dispute correctly previews as the policy default, which is a feature: it shows the attestation is what drives the verdict.

---

## 2026-07-21: Session 24, native iPhone architecture decision

Found: the repository specified Flutter as a fixed buyer-app choice, but the owner wants an iPhone-first product for personal Swift ownership, App Store delivery, and a long-term enterprise-quality native experience. The product boundaries do not require cross-platform UI sharing: contracts, QR payloads, backend APIs, and the web verifier are already the stable interoperability layer. The main native risk is EVM key custody and transaction encoding, not SwiftUI.

Decided: replace Flutter-first with a native Swift iPhone client targeting iOS 17+. The new blueprint in docs/recourse/recourse-ios-architecture.md uses SwiftUI, Observation, structured concurrency, NavigationStack, AVFoundation, PhotosUI, URLSession, Keychain, LocalAuthentication, and a protocol-isolated ContractGateway. Start with web3swift behind the gateway, pin and review the package, and keep the signer replaceable. The demo signer is testnet-only and stores an encrypted keystore behind Keychain user presence. It must not claim Secure Enclave Ethereum signing because Secure Enclave does not directly provide secp256k1 signing. Swift calls previewVerdict and never becomes a third verdict implementation. App Store and TestFlight are the first release path; enterprise distribution is separate and only applies to eligible internal deployments. Android is deferred and may use Flutter later against the same external contracts.

Rules earned: choose native UI independently from protocol portability. Preserve future clients through versioned QR payloads, documented APIs, generated addresses and ABIs, and chain-authoritative state rather than forcing a shared cross-platform presentation layer. Put replaceable cryptography and custody behind a narrow signer protocol before building feature screens.

---

## 2026-07-21: Session 23, attestor bot (EIP-712 signer + demo endpoints)

Found: the read backend was live but the dispute loop had no attestor. Per the docs the attestor is a binary in the backend crate that signs an objective delivery fact (EIP-712) and pushes the transaction; it never decides outcomes (R4, PRD "arbiter has no discretion"), the onchain PolicyEngine computes the verdict. Researched the exact mechanism with three subagents before coding (R12): the contract side (hand-rolled EIP-712, domain RecourseAttestor/1/chainId/escrow, struct Attestation(uint256 paymentId,uint8 attType,uint8 value,uint64 deadline), raw ecrecover requiring 65-byte r||s||v low-s v in {27,28}), the seeder's working viem signing as the byte-exact reference, and the doc spec (POST /api/demo/attest {paymentId,value}, DEMO_MODE-gated, value caller-supplied).

Built: src/attestor.rs. An alloy sol! Attestation SolStruct plus an IEscrowWrite interface (submitAttestation, resolve, attestationDigest). AttestorClient holds a wallet-bearing provider and a PrivateKeySigner; attest() signs eip712_signing_hash via sign_hash_sync, lays out r||s||v with v = 27 + y-parity, and submits submitAttestation (moves no funds); resolve() settles (moves funds). Config gained ATTESTOR_PK (Option, testnet throwaway R7); main.rs builds the client only when DEMO_MODE and the key are set, running a boot self-check (local digest vs onchain attestationDigest) that warns rather than crashing reads. routes.rs added POST /api/demo/attest and /api/demo/resolve, gated on the attestor being present, logging each action (R8), with resolve's fund movement called out.

Verified: byte-exact signing proven WITHOUT the attestor key. cast returned the onchain attestationDigest(5,1,2,4000000000) = 0x6132a1316846f33d5f241f793988e1d0eeaf5a53c0b292560654b1b92102a25d; a unit test asserts the local alloy eip712_signing_hash equals it, and a second test signs with a random key and confirms recover_address_from_prehash round-trips with v in {27,28}. So a signature from the real attestor recovers to the attestor onchain and submitAttestation accepts it. cargo test and clippy --all-targets clean. Ran the rebuilt server: with no ATTESTOR_PK the endpoints correctly report 503 disabled and the log says attestor bot disabled. Not yet exercised end to end against a live disputed payment (needs a fresh Disputed payment and the key; the seeded 5/6 are settled) and resolve is money-moving (R13: verify on anvil or a logged testnet run before a live demo).

Rules earned: for a cross-language signer, pin correctness with a golden digest read from the deployed contract (cast) and a sign->recover round-trip, so byte-exact EIP-712 compatibility is proven without ever holding the production key. Sign the prehashed eip712_signing_hash rather than a typed-data sync helper, since that method is the one tied to the onchain digest.

---

## 2026-07-21: Session 22, wire the merchant lists to the indexer read API

Found: the payments, disputes, receipts, and protection pages still rendered hardcoded arrays (CloudCompute, FileStore, and similar fictional merchants) as Server Components. With the backend read API in place, these should show the real seeded onchain payments, which is the "not mocks" payoff the owner asked for.

Built: web/lib/api.ts (typed client for /api/payments, /api/disputes, /api/policies, /health with USDC and enum formatters mirroring RecourseEscrow.Status and the engine claim-type table), web/lib/use-live.ts (a small fetch-on-mount hook exposing loading, data, and error), and web/components/live-notice.tsx (loading, indexer-offline, and empty states). Converted the four list pages to client components that render live payments: amounts formatted from u128 base units (R1), merchants and buyers shown as short addresses, statuses mapped from the Status enum, disputed rows linking to the dynamic verifier at /verify/{id}, and metrics computed from the live set. Protection joins payments to policy dispute windows to show a real progress bar. When the backend is unreachable the pages show an honest "indexer offline" notice rather than fabricated rows, and the chain-direct verifiable sections stay untouched. NEXT_PUBLIC_BACKEND_URL configures the base (defaults to localhost:8080).

Verified: tsc and eslint clean; production build green, 16 routes, the landing still static and the four list pages now client shells that fetch at runtime. Then run live end to end: docker Postgres plus the backend indexed all 8 seeded payments and policy 1 from Arc (health indexedPayments 8), and the API payloads match the web formatters exactly (payment 5 refundBps 10000 matched, payment 6 refundBps 0, policy 14 day window, verdict hashes from previewVerdict). CORS reflects the browser origin. The web reads NEXT_PUBLIC_BACKEND_URL, so its dev server must be restarted after that env is set.

Port gotcha (this machine): 5432 was held by another project's postgres (xend), and 5433 by a native homebrew postgres bound to 127.0.0.1 which shadows the docker wildcard bind, so localhost:5433 silently hit the wrong server and failed with role recourse does not exist. Resolved by moving the container to a free port (55432 via ops/.env) and pointing DATABASE_URL at it; also moved the backend off 8080 (held by qent) to 8090 via web/.env.local. Committed default is now 5433 to dodge the common 5432 clash.

Rules earned: when a real data source can be offline, degrade to an explicit offline state, never to fabricated data that reads as real, and keep the independently verifiable sections chain-direct so they work even when the projection is down. When a host TCP port maps to a docker container, a native process bound to the specific loopback address wins over docker's wildcard bind, so always confirm which server actually answers before trusting the port.

---

## 2026-07-21: Session 21, backend code-review pass (three P1 correctness fixes)

Found: a review of the Session 20 backend flagged three real correctness bugs. (1) In indexer.rs the disputed-payment verdict came from preview_verdict(...).ok(), so a transient RPC failure became None and the upsert overwrote the cached verdict columns with NULL, blanking a disputed payment's verdict for a tick. (2) The projection tables were keyed by paymentId alone with no deployment scoping; paymentIds restart at 1 on a redeploy, so a prior escrow's rows could masquerade as current. (3) /health ran count_payments(...).unwrap_or(0) and returned 200 "ok" even when Postgres was unreachable. The review also raised P2s (state-poller cannot reconstruct tx hashes or events, serial per-record reads, raw startup SQL without migration history, permissive CORS once write routes land) and zero tests.

Fixed: (1) preview failure now logs and yields None while the upsert COALESCEs each verdict column against the stored row, so a transient failure keeps the last-good verdict (verdicts are deterministic and one-way, so old is always safe). (2) added an index_meta single-row table recording the active escrow and chainId; on startup reset_if_deployment_changed truncates payments and policies when the configured deployment differs, so stale rows never linger (the chain is the source of truth, so a truncate loses nothing). (3) /health now depends on the DB probe and returns 503 degraded when the count query fails.

Decided: accept the reviewer's strategic call. The backend stays a thin, rebuildable projection for the merchant lists and disputes; do not grow it into an event indexer for the demo. The P2s are acknowledged and deferred (tighten CORS when attestor write routes arrive; a full event indexer only if the receipts view needs tx hashes). Next backend value is the attestor bot, not more read plumbing. cargo clippy --all-targets clean (zero warnings). Still compile-verified only, not run against live Postgres plus Arc.

Rules earned: a projection upsert must never let a transient source read erase a good cached value (COALESCE, do not overwrite with NULL), and a rebuildable projection of a single deployment should record and check that deployment's identity so a redeploy wipes rather than shadows the old rows.

---

## 2026-07-21: Session 20, Rust backend indexer and read API (actix-web)

Found: the merchant app surfaces still ran on mock arrays. The architecture calls for a Rust backend that indexes chain state, serves reads, stores evidence, and signs demo attestations, with no business logic (R4) and no third verdict implementation (R2). The owner asked for actix-web rather than axum.

Decided: start the backend with the read half (indexer plus read routes); defer evidence store and attestor bot. Use a state-polling indexer (read every payment and policy each tick) rather than event-log decoding, which is simpler and robust at demo scale. Verdicts come from the onchain previewVerdict, never recomputed (R2). Addresses load from deployments/arc-testnet.json at startup (R3). Keep the verifier and policy reads chain-direct on the web so they stay independently verifiable without trusting this service.

Built: backend/ as a Cargo crate with actix-web, actix-cors, sqlx (Postgres, runtime queries so no live DB at compile time), and alloy for chain reads. src/chain.rs models the escrow and registry via sol! and reads paymentCount, getPayment, previewVerdict, policyCount, getPolicy, policyHash. src/indexer.rs polls Arc every INDEX_INTERVAL_SECS and upserts payments and policies, previewing verdicts only for filed disputes. src/db.rs holds the schema (migrations/0001_init.sql, run idempotently on startup), models, upserts, and read queries. src/routes.rs serves /health, /api/payments (optional merchant filter), /api/payments/{id}, /api/disputes, /api/policies, /api/policies/{id}. ops/docker-compose.yml provides Postgres; backend/README.md is the runbook.

Verified: cargo check is clean (zero warnings). alloy 1.8 resolved; the only fix needed was on_http to connect_http. Not yet run against live Postgres plus Arc (needs docker compose up and cargo run locally), so the indexer loop and endpoints are compile-verified but not yet exercised end to end.

Rules earned: a state-polling indexer is a legitimate, lower-risk first cut before event-log decoding, and a read-only backend earns R4 compliance by pulling verdicts from previewVerdict rather than ever recomputing them.

---

## 2026-07-21: Session 17, wallet connect, onchain policy publish, and R5 reconcile

Found: the onboarding (Session 16) set up an account but the web still had no real wallet. The PRD F1 specifies "connect wallet on web" with wagmi v2 and the injected connector for testnet, and publishing a policy onchain was the last open web item. The onboarding also offered Buyer as a web role, which conflicts with R5 (buyer lives on the Flutter mobile app; merchant and LP on the web).

Decided: add wallet connect with wagmi v2 and the injected connector only, scoped to the (merchant) route group via a Providers wrapper so the marketing landing stays static and untouched. The connected address is the policy merchant, so the builder previews the exact hash that registerPolicy will pin. Reconcile R5 by making Merchant the web default, dropping Buyer as a selectable web workspace, and framing buyers as mobile. Hold the vault deposit transaction: it moves USDC, so per R13 it needs a funded wallet to verify, which is not possible here.

Built: lib/wagmi.ts (Arc chain plus injected, ssr true), components/providers.tsx mounted in app/(merchant)/layout.tsx, components/connect-wallet.tsx (connect, disconnect, shortAddress) wired into the shell topbar with the connected address shown on the profile. The policy builder now reads the connected address as the merchant and gained a Publish to Arc panel that calls registerPolicy through useWriteContract and links the confirmed transaction. Added registerPolicy and policyCount to the registry ABI. R5: default role merchant, onboarding web roles are merchant and liquidity provider with a buyers-use-mobile note. next.config.ts ignores the optional connector deps that wagmi bundles but we never use (@x402/* via the Coinbase SDK, React Native async storage via the MetaMask SDK, pino-pretty via WalletConnect).

Verified: tsc and eslint clean; production build green with zero module-not-found warnings, 16 routes, the landing still statically prerendered. The onchain publish path is ABI-correct and compiles, but the actual transaction needs a funded Arc wallet to exercise (untested against a live wallet here).

Rules earned: when a wallet library bundles connectors you do not use, scope its provider to the routes that need it and ignore the unused connectors' optional deps rather than installing them, and keep the preview identity (merchant address) equal to the transaction signer so the previewed hash equals the onchain one.

---

## 2026-07-21: Session 19, Peec-inspired focused onboarding

Found: the previous onboarding used a persistent progress sidebar and oversized editorial headings, making a short setup flow feel like an admin dashboard. Research into Peec AI's hands-on onboarding showed a tighter pattern: magic-link entry followed by a few focused screens for business type, brand details, location, and suggested topics. Its visual layout keeps the active form compact on the left and uses contextual product or customer proof on the right.

Decided: adapt the interaction principle, not Peec's brand. Recourse now presents one decision per screen with compact sans-serif typography, dense selectable rows, a clear black action button, and four-step progress in the supporting panel. Replace Peec's testimonial with truthful Recourse product proof based on implemented workspace, policy, settlement, and verifier capabilities.

Built: removed the persistent setup checklist, moved the active onboarding form into a focused left panel, added a faded dashboard preview and step-aware proof card on the right, tightened every step's spacing and controls, sanitized old buyer roles back to merchant on web, and retained a single-column mobile flow.

Green: web typecheck, lint, all four onboarding steps exercised in-browser, personalized completion verified, 390px mobile width with zero overflow, no console warnings, and git diff check.

Rules earned: reference products should inform interaction hierarchy, not supply borrowed brand content or invented social proof.

---

## 2026-07-21: Session 18, real photography for the sign-in story

Found: the solid green sign-in panel still felt synthetic after removing the decorative gradient.

Decided: use real editorial photography rather than crypto circuitry or generated abstract art. A portrait aerial ocean photograph by Alex Perez provides natural movement, a premium dark palette, and enough negative space for the headline. The image is free under the Unsplash License, stored locally, and documented beside the asset. A single flat overlay exists only for text contrast, not decoration.

Built: searched Unsplash and Pexels candidates, compared a real ocean photograph against an abstract light photograph, selected the ocean crop, resized it to 1440 by 1922, compressed it to a 384 KB WebP, and installed it as the responsive sign-in story background.

Green: source and license recorded, asset localized, and git diff check clean.

Rules earned: prefer real editorial imagery with documented provenance over decorative gradients when a brand surface needs atmosphere.

---

## 2026-07-21: Session 17, replace translucent status decoration with purposeful motion

Found: the soft green status pill and pale shield bubble looked generic and decorative rather than connected to live product state.

Decided: status decoration should communicate behavior. Use the existing ping Lottie for Arc network activity and the existing burst Lottie behind a crisp solid protection mark. Avoid translucent gradient decoration when a real icon or state animation can carry the meaning.

Built: reusable LivePulse and ProtectionMark components, applied them to landing network labels, the payment proof label, the protected-payment receipt, and the dashboard protected-payments summary. Removed the soft fill from the landing eyebrow and replaced the sign-in story gradient with a solid product color.

Green: web typecheck, lint, browser visual check, zero browser console warnings, and git diff check.

Rules earned: purposeful motion should represent live state, not decorate empty space.

---

## 2026-07-20: Session 16, fintech-style onboarding and profile-driven dashboard

Found: the landing page previously skipped directly to a dashboard with a hardcoded user, so there was no credible path from first visit to "Good morning, Frank." Starting with wallet connection would also make the product feel like a DeFi console rather than payment infrastructure.

Decided: D27, use a familiar fintech sequence: sign in, choose the first workspace role, complete a short profile, review role-specific setup, then enter the dashboard. Buyer, Merchant, and Liquidity Provider are product roles; developers continue through documentation rather than becoming an account type. Wallet connection remains secondary and appears only when an onchain action needs it. Until a real auth and embedded wallet provider is integrated, every auth action is explicitly labeled as a simulated testnet demo and no credentials are collected.

Built: /signin with Google, passkey, email, and existing-wallet entry options; /onboarding with four responsive steps and tailored Buyer, Merchant, and Liquidity Provider setup content; a small localStorage-backed demo profile module; personalized dashboard greeting, initials, and profile name; and landing Launch App links routed through sign-in. Verified the complete click path with a renamed user through to the personalized dashboard. Mobile checks at 390px found zero horizontal overflow on both new routes and no console errors.

Green: web typecheck, lint, production build, and git diff check.

Rules earned: none new. Reinforced R6 by clearly separating simulated onboarding from real authentication and wallet infrastructure.

---

## 2026-07-20: Session 15, marketing landing page at the root

Found: the app had no front door. The root redirected straight to /dashboard, so there was nowhere to explain the product to a first-time visitor or a judge. The owner supplied a landing reference whose display headlines are a serif, which conflicts with the Geist-everywhere decision from Session 12.

Decided: build the landing to match the reference and make it the root route, with Launch App and Start building going to /dashboard and Explore the demo going to /verify/5. Resolve the font conflict by scope: add a --serif token (Georgia, offline, no CDN) used only for the landing headlines under a .landing scope, so the app keeps Geist and only the marketing page gets the editorial serif. Flag this so the owner can unify later if they want serif headlines app-wide.

Built: components/landing-page.tsx and the root page, a full landing with a sticky nav (brand, links, Arc Testnet chip, Launch App), a two column hero (serif headline, subcopy, two CTAs, social proof) beside an overlapping product mockup collage (dashboard card, a scalloped protected-payment receipt, a dispute-status card with a timeline, and a floating escrow-earnings sparkline chip), a Powered by Circle stack strip (Arc, USDC, USYC, Gateway, CCTP, Circle Wallets, Paymaster, Nanopayments), a four card feature grid, and a footer. All landing styles are scoped under .landing and collapse cleanly at 1080, 860, and 640 px.

Verified: web tsc, eslint, and the production build are green (14 routes). The root returns 200 and renders the landing (no longer a redirect); the hero CTAs resolve to /dashboard and /verify/5.

Rules earned: when a new reference conflicts with a standing font decision, scope the exception to the surface that needs it rather than reversing the decision app-wide, and name the choice so the owner can decide whether to generalize it.

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

## 2026-07-20: Session 13, full landing page product narrative

Found: after the credibility pass, the landing page still ended after four feature cards and did not explain the mechanism, public verification, user roles, vault economics, or the prototype’s limits. The short page looked polished but left judges and prospective users to infer the core product story.

Decided: expand with product-specific context rather than generic marketing blocks. The narrative order is value proposition, capability summary, four-step flow, live verification proof, aligned buyer and merchant and LP incentives, vault return equation, operational FAQs, then final demo actions.

Built: a four-step workflow section, live Solidity versus browser hash proof card, three audience value cards, vault economics section, five-question semantic FAQ accordion, and closing launch banner. Navigation now points About to the workflow and For Merchants to the dashboard. Added responsive layouts for every new section, including stacked workflow cards, single-column audience cards, a mobile vault equation, and readable FAQ spacing.

Verified: TypeScript, ESLint, and the production build are green. Desktop structure renders once for every section, mobile width remains exactly 390 pixels with no overflow, the FAQ anchor and accordion render correctly below the sticky header, and the browser console is clean. The full-page browser capture repeated content due to a stitching artifact; DOM counts confirmed one instance of each section.

Rules earned: landing page length should come from answering real product questions in narrative order, not from adding decorative filler sections.

---

## 2026-07-20: Session 12, landing page credibility and responsive polish

Found: the landing page claimed a broader Circle integration stack than the prototype currently implements, showed a protected total that did not equal its visible payments, mixed developer and product CTAs, used placeholder portrait avatars as social proof, and stacked four large mockup cards vertically below 1400 pixels. The desktop collage also allowed floating cards to escape its visual boundary.

Decided: make every above-the-fold claim demonstrable. The eyebrow now says Live on Arc Testnet, the trust row reports the live contract, eight seeded payments, and hash-verified verdicts, and the stack lists Arc Testnet, USDC, the USYC adapter, and the deterministic engine only. The primary CTA opens the live proof demo and developer documentation is secondary.

Built: reconciled the protected total to $464, rewrote the hero around immutable refund rules and evidence-based outcomes, removed placeholder avatars and unsupported integration marks, contained and rebalanced the desktop product collage, improved body contrast, and replaced the laptop breakpoint with a stable two-column layout. Mobile now hides decorative side cards and shows one readable protected-payment receipt.

Verified: production build, TypeScript, and ESLint are green. Visual checks passed at 1440 by 900 and 390 by 844. Mobile document width equals viewport width with no horizontal overflow, and the browser console is clean.

Rules earned: marketing claims must map to implemented capabilities, and decorative product collages need a single contained mobile focal point rather than stacking every desktop layer.

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
