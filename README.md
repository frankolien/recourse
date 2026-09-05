<p align="center">
  <img src="web/public/brand/recourse-mark.png" width="72" alt="Recourse" />
</p>

<h1 align="center">Recourse</h1>
<p align="center"><b>The money app for dollars on your phone.</b></p>
<p align="center">
  <a href="https://testflight.apple.com/join/rWWg1wCb">iOS beta on TestFlight</a> ·
  <a href="https://recourse-arc.vercel.app">Site</a> ·
  <a href="https://x.com/useRecourse">@useRecourse</a> ·
  <a href="https://api.frankolien.com/health">Live API</a>
</p>

---

Recourse is a money app for USDC on Arc, Circle's chain for dollars. You send to a
person by their @handle, not an address. Every payment is signed by two keys, one in
the phone and one in your iCloud Keychain, and there is no seed phrase to write down.
Fees are paid in the same dollars you hold, so there is no second token to buy.

It is iOS only. The web is the site that points at the app, plus the console for
Olien, the team account protocol described below.

Everything here runs on Arc testnet (chain 5042002). Nothing is real money yet. Arc
mainnet opens on 2026-09-16 and the app moves after the deployments on it are verified.

## What the app does

- **Send by name.** Type an @handle, an amount, a note. The app resolves the name to
  one account and shows you who before you sign.
- **Request money.** An invoice fixes the amount, the date and who pays. They answer
  with one signature and no gas on their side; you collect when you like.
- **Cheques.** Write one, they cash it later, without being online when you write it.
  Void it any time before it is cashed. Built on EIP-3009 `transferWithAuthorization`.
- **Earn.** Put idle USDC into the vault and take it out whenever.
- **Convert.** USDC to EURC at a rate the app checks against the market before you
  sign. If the pool is off market the button stays grey and the screen says why.
- **History** grouped by day, and a balance that never turns into a zero on a bad
  connection: a failed read keeps the last number and says how old it is.

## The account

Every Recourse account is a [Safe](https://safe.global) deployed on Arc with three
keys and a 2 of 3 threshold:

| Key | Where | Can spend |
| --- | --- | --- |
| Device | Secure Enclave, P-256, Face ID | yes, with the cloud key |
| Cloud | iCloud Keychain, secp256k1 | yes, with the device key |
| Recovery | sealed by the server, PIN-wrapped | no, recovery only |

Lose the phone: sign in on a new one, the cloud key arrives with iCloud, and a code to
your email swaps the device key over. Lose the cloud key: your recovery PIN brings it
back. Recourse never holds a key that can spend. The design is in
[docs/keys-and-recovery.md](docs/keys-and-recovery.md).

Verified on Arc testnet: Safe 1.4.1 at its canonical addresses, EntryPoint v0.7, the
Pimlico bundler, the RIP-7212 P-256 precompile, and USDC accepting EIP-1271 so cheques
from a smart account cash on chain. The P-256 owner contract that lets a Secure Enclave
key own a Safe is [`P256Owner.sol`](contracts/src/P256Owner.sol), factory
`0xBb27F2339a48aE263527b3F2DD871ec12a7E7ce8`.

## Olien: accounts for teams

Olien is our own account protocol on Arc, a peer of Safe and Squads rather than a
product on top of one. One contract holds the account's policy: a threshold, a spending
limit that does not need a vote, a time lock on membership changes, a veto for the
members who did not sign, and a recovery path with a co-signed delay. Members can be
wallets, passkeys, phones through the P-256 precompile, or other accounts such as a
Recourse account through its Safe.

- Spec: [docs/treasury/10-account-spec.md](docs/treasury/10-account-spec.md). Design
  record, security model, algorithms and roadmap sit beside it in
  [docs/treasury/](docs/treasury/).
- Contracts: [contracts/src/olien/](contracts/src/olien/), tests in
  [contracts/test/olien/](contracts/test/olien/).
- Service: the transaction queue, relayer and indexer in the backend under
  `/api/treasury`, contract in [docs/treasury/11-service-api.md](docs/treasury/11-service-api.md).
- Console: [web/app/olien/](web/app/olien/), Squads-shaped, wallet sign-in, passkey
  members. Behind a coming-soon page in production until it has been run on a phone.
- iOS: the Team area, where a Recourse account approves a treasury's payment with Face
  ID and can veto a scheduled change.

Arc testnet, CREATE2 with fixed salts:

| Contract | Address |
| --- | --- |
| OlienFactory | `0xaF8c108D09E6A159D4dcE0919Ca6A81d6019f131` |
| Olien implementation | `0x8BFf8CCe4edbE882a21197D3942978CCd06fA427` |
| OlienVerifier (P-256 and WebAuthn) | `0xE196558Ce080229B256dDE6e62CDA2B051B882fC` |
| SubAccount implementation | `0xDfc576536187eF72689c514f8c7ea6487960a637` |

Status: Phase 3 of the roadmap in
[docs/treasury/08-roadmap-and-grants.md](docs/treasury/08-roadmap-and-grants.md).
Proof runs, with transaction hashes, are recorded there phase by phase.

## Repository

```
mobile/      SwiftUI app. No wallet SDK; the Secure Enclave, Keychain and Safe code is ours
backend/     Rust (actix, sqlx, alloy): accounts, handles, cheques, invoices, Olien service, indexers
web/         Next.js: the site at /, the Olien console at /olien
contracts/   Foundry: Olien, P256Owner, the escrow and policy engine, the testnet FX venue
engine/      TypeScript mirror of the policy engine, kept in parity by golden vectors
packages/    The golden vectors shared by forge and vitest
deployments/ Arc addresses. Everything else reads addresses from here
docs/        Product, keys and recovery, treasury (Olien), social
ops/         Deploy, codegen, vault and demo scripts
```

The escrow, policy engine and settlement vault come from where this started: a
buyer-protection product where a dispute is computed from an immutable policy rather
than decided by a person. That checkout is retired from the app, and the primitives
stay because invoices with terms and team spending rules cash them in. The record of
that work, with its transaction hashes, is in [log.md](log.md).

## Running it

- **iOS:** `cd mobile && ruby scripts/generate_project.rb && open Recourse.xcodeproj`.
  Tests: `xcodebuild -project Recourse.xcodeproj -scheme Recourse -destination 'platform=iOS Simulator,name=iPhone 17' test`.
- **Backend:** `cd backend && cargo run`, with `DATABASE_URL` pointing at a Postgres and
  the variables in `.env.example`. Tests: `cargo test`.
- **Web:** `cd web && npm install && npm run dev`. The console needs
  `NEXT_PUBLIC_OLIEN_CONSOLE=on` and a backend URL.
- **Contracts:** `cd contracts && forge test`. The Olien suite etches Arc's EntryPoint
  v0.7 bytecode and a P-256 verifier at the precompile's address.

Arc's USDC is a chain precompile, so no local fork can move it. Anything that moves
money is verified with small amounts on testnet, and every claim in the docs is tied to
a transaction hash.

## What is not done

Testnet only, contracts unaudited, no push notifications, and no fiat on-ramp reaches
Arc yet. The audit is Phase 4 of the roadmap; the consumer account stays on Safe for
real money until it clears. Olien is a console behind a coming-soon page until it has
run on a phone against the service.

---

Built by one person. Session-by-session engineering record in [log.md](log.md).
