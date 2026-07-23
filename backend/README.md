# recourse-backend

Indexer and read API for Recourse. Indexes Arc escrow state into Postgres and
serves reads. It holds no business logic (R4): verdicts come from the onchain
`previewVerdict` (R2), and contract addresses come from
`deployments/arc-testnet.json` (R3). Testnet only (R7).

## Run

```
# 1. Postgres
docker compose -f ../ops/docker-compose.yml up -d

# 2. Config
cp .env.example .env        # defaults point at local Postgres and Arc dRPC

# 3. Run (creates tables, starts the indexer, serves the API)
cargo run
```

### Sign in with Apple key

The local backend configuration expects the downloaded Apple private key at:

```text
backend/secrets/AuthKey_XY9C96WBZL.p8
```

The `backend/secrets/` directory ignores private keys. Keep the key on the backend only.
The local `.env` references it through `APPLE_PRIVATE_KEY_PATH`; deployed environments
should store the same key in their secret manager rather than the repository.

The indexer polls Arc every `INDEX_INTERVAL_SECS` (default 15), reading every
payment and policy into Postgres and pulling each disputed payment's verdict from
the contract's `previewVerdict`.

## Deploy (Railway)

`Dockerfile` (repo root, build context = repo root) and `railway.json` drive the deploy.
Railway builds the Dockerfile; the image bundles `deployments/arc-testnet.json` (contract
addresses are read from it at runtime, R3), and `sqlx::migrate!` runs the migrations on
boot, so a fresh database self-provisions. Railway injects `PORT` and the app binds to it;
`/health` is the healthcheck (pinned in `railway.json`). Testnet only (R7).

1. **New project -> Deploy from repo.** Leave the service root directory at the repo root:
   the Dockerfile copies from `backend/` and `deployments/`, so it needs the whole repo as
   build context. `railway.json` pins the Dockerfile builder.
2. **Add a PostgreSQL database** to the project. In the backend service Variables, set
   `DATABASE_URL = ${{Postgres.DATABASE_URL}}` (a reference to the DB service).
3. **Add a Volume** to the backend service mounted at `/data`. The image already points
   `EVIDENCE_DIR` at `/data/evidence-store`, so evidence blobs survive redeploys.
4. **Set the service Variables** (secrets):

   ```
   CORS_ALLOWED_ORIGINS=https://<your-web-domain>
   GOOGLE_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
   GOOGLE_IOS_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com
   ADMIN_API_KEY=<openssl rand -hex 32>
   WEBAUTHN_RP_ID=<your-domain>            # passkeys; see below
   WEBAUTHN_RP_ORIGIN=https://<your-domain>
   # Optional attestor + automated resolver:
   ATTESTOR_PK=0x<testnet-throwaway>
   ATTESTOR_AUTO_RESOLVE=true
   # Optional Sign in with Apple: APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_CLIENT_ID (+ the .p8)
   ```
5. **Deploy**, then generate a public domain (service Settings -> Networking -> Generate
   Domain). Confirm `https://<app>.up.railway.app/health` returns status/chainId/indexedPayments,
   and check the deploy logs for "listening on" and the indexer ticking.

Point the web and iOS clients at the generated Railway URL. **iOS passkeys need a custom
domain**, not `*.up.railway.app`: `WEBAUTHN_RP_ID` must be a domain you control and can serve
`/.well-known/apple-app-site-association` from, so attach a custom domain in Railway and use
it for the WebAuthn RP id/origin.

## Endpoints

| Method | Path | Auth | Returns |
|---|---|---|---|
| GET | `/health` | none | status, chainId, indexedPayments |
| GET | `/api/payments` | none | payments; filters `?merchant=` `?buyer=`, paging `?limit=` `?offset=` |
| GET | `/api/payments/{id}` | none | one payment with its verdict |
| GET | `/api/payments/{id}/evidence` | none | the payment's verified evidence list (re-checked against chain on read) |
| GET | `/api/disputes` | none | payments with a filed claim; `?buyer=` `?limit=` `?offset=` |
| GET | `/api/policies` | none | all indexed policies |
| GET | `/api/policies/{id}` | none | one policy with its rules and hash |
| POST | `/api/auth/challenge` | none | issue a one-time nonce for wallet-signature auth |
| POST | `/api/auth/apple/challenge` | none | issue a one-time nonce for native Apple authentication |
| POST | `/api/auth/apple` | Apple code | verify Apple and issue a Recourse account session |
| POST | `/api/auth/google` | Google ID token | verify a Google ID token (web or iOS audience) and issue a session |
| POST | `/api/auth/email/register` | email + password | create an email/password account and issue a session |
| POST | `/api/auth/email/login` | email + password | verify an email/password pair and issue a session |
| POST | `/api/auth/passkey/register/start` | none | begin a WebAuthn registration for an email; returns creation options + a challenge id |
| POST | `/api/auth/passkey/register/finish` | passkey attestation | verify the authenticator, create the account, issue a session |
| POST | `/api/auth/passkey/login/start` | none | begin authentication for an email's passkeys; returns request options + a challenge id |
| POST | `/api/auth/passkey/login/finish` | passkey assertion | verify the assertion, bump the counter, issue a session |
| POST | `/api/auth/refresh` | refresh token | rotate an account session |
| POST | `/api/auth/logout` | account bearer | revoke an account session |
| GET | `/api/me` | account bearer | current Recourse account profile |
| POST | `/api/evidence` | buyer sig | store an evidence blob, returns its keccak256 hash |
| POST | `/api/evidence/manifest` | buyer sig | verify an evidence list against the onchain `evidenceRoot`, then record it |
| POST | `/api/demo/attest` | admin | DEMO_MODE: sign a delivery attestation and submit it |
| POST | `/api/demo/resolve` | admin | DEMO_MODE: settle a disputed payment (moves funds) |

Reads are public because payment state is public chain data (the mobile app can also read
Arc directly). Amounts are USDC (6 decimals) as decimal strings. Addresses are lowercased.
Lists page with `?limit=` (default 100, max 500) and `?offset=`.

## Authentication

Two boundaries, chosen so each matches who is really acting:

**Account sessions** use native Sign in with Apple. The iPhone first requests
`POST /api/auth/apple/challenge`, hashes that server nonce into Apple's authorization
request, then sends Apple's one-time authorization code back to `POST /api/auth/apple`.
The backend creates an ES256 client secret from the local `.p8` key, exchanges the code
directly with Apple, verifies Apple's RS256 identity token, audience, expiry, and nonce,
then returns opaque access and refresh tokens. Only token hashes are stored in Postgres.
Access tokens last 15 minutes; refresh tokens last 30 days and rotate on every refresh.

**Sign in with Google** (`POST /api/auth/google`) takes the ID token from Google Identity
Services. The backend verifies its RS256 signature against Google's JWKS, the issuer, the
expiry, and that the audience is one of the configured OAuth client ids. Set
`GOOGLE_CLIENT_ID` (web) and, for the iOS app, `GOOGLE_IOS_CLIENT_ID`; the same endpoint
serves both because it accepts either audience. No server nonce is needed: Google's token
is already short-lived and audience-bound.

**Email and password** (`POST /api/auth/email/register`, `.../login`) is the no-provider
path. The account (`provider='email'`) stores an Argon2id hash, never the plaintext.
Register returns `409` if the email is taken and `400` for a malformed email or a password
under 8 characters; login returns a uniform `401` so it never reveals which emails exist.
This build has no verification email; the address is trusted on submission.

**Passkeys (WebAuthn)** are an email-first ceremony in two round-trips each. Register:
`register/start` checks the email is free and returns the WebAuthn creation options plus a
single-use `challengeId`; the authenticator (iOS platform passkey) produces an attestation
that `register/finish` verifies before creating the `provider='passkey'` account, storing
the credential, and issuing a session. Login mirrors it (`login/start` → `login/finish`),
verifying the assertion and bumping the credential's signature counter. The in-flight
ceremony state (`PasskeyRegistration`/`PasskeyAuthentication`) is parked in a single-use,
5-minute `webauthn_ceremonies` row, consumed by `DELETE ... RETURNING` so a challenge is
good for exactly one finish. Passkeys are enabled only when `WEBAUTHN_RP_ID` and
`WEBAUTHN_RP_ORIGIN` are set (otherwise the endpoints return `503`).

For **iOS** passkeys, `WEBAUTHN_RP_ID` is the bare domain the app is associated with (e.g.
`recourse.app`) and `WEBAUTHN_RP_ORIGIN` is `https://<rp_id>` (iOS platform passkeys set the
clientData origin to exactly that). The app needs the `Associated Domains` entitlement
(`webcredentials:recourse.app`) and an `apple-app-site-association` file served at
`https://recourse.app/.well-known/apple-app-site-association` listing `TEAMID.bundle.id`
under `webcredentials`. Because that requires a real HTTPS domain, iOS passkeys are tested
against the deployed backend, not localhost.

All of these sign-in paths mint the same opaque access + refresh tokens as Apple.
These account tokens authorize profile and onboarding APIs only. They do not replace the
wallet signature required for payment-scoped writes.

**Buyer writes** (evidence upload, manifest) use a wallet EIP-712 signature. The caller has
no account: they prove they are the payment's on-chain buyer by signing. Flow:

1. `POST /api/auth/challenge` returns `{nonce, expiresAt}` (a single-use nonce, 5 min TTL).
2. The buyer signs this EIP-712 typed message with their wallet key:
   - domain `{ name: "Recourse", version: "1", chainId }` (no verifyingContract)
   - type `Authorization(string action,uint256 paymentId,address walletAddress,uint256 chainId,bytes32 bodyHash,bytes32 nonce,uint256 expiresAt)`
   - `action` is `"evidence.upload"` or `"evidence.manifest"`; `bodyHash` is
     `keccak256(exact request body bytes)`; `nonce`/`expiresAt` come from step 1.
3. Send the request with header `X-Recourse-Auth: base64(json envelope)`, where the
   envelope is `{action, paymentId, walletAddress, chainId, bodyHash, nonce, expiresAt, signature}`.

The backend recovers the signer, requires it to equal `getPayment(paymentId).buyer` on the
live chain, checks the body hash, chainId, action, and freshness, and consumes the nonce
atomically so a captured signature is good for exactly one write. Nothing is stored on a
signature that does not verify.

**Admin routes** (`demo/attest`, `demo/resolve`) use a bearer token: `Authorization:
Bearer $ADMIN_API_KEY`. These push the attestor's own txs and move funds, so they are
operator tools, never the public or the mobile app (which resolves directly on Arc). They
fail closed: with no `ADMIN_API_KEY` set, no one can reach settlement.

## Attestor bot (demo)

The attestor signs one objective fact, delivery status, and pushes the transaction
(R4: no business logic; the onchain PolicyEngine computes the verdict, the attestor
never decides it). It is enabled only when `DEMO_MODE=true` and `ATTESTOR_PK` is set
to the escrow's attestor key (R6, R7). The signing is byte-verified against the
deployed contract: `cargo test` asserts the local EIP-712 digest equals the escrow's
`attestationDigest`, so a produced signature is accepted onchain.

```
# value: 1 DELIVERED, 2 NOT_DELIVERED. Payment must be in the Disputed state.
# Admin-only: needs Authorization: Bearer $ADMIN_API_KEY (fail-closed without it).
curl -X POST localhost:8080/api/demo/attest  -H "authorization: Bearer $ADMIN_API_KEY" -H 'content-type: application/json' -d '{"paymentId":7,"value":2}'
curl -X POST localhost:8080/api/demo/resolve -H "authorization: Bearer $ADMIN_API_KEY" -H 'content-type: application/json' -d '{"paymentId":7}'
```

`attest` moves no funds (it only stores the attested value). `resolve` settles and
moves USDC, so verify it against a real node before a live run (R13) and log demo
runs (R8). To exercise the loop you need a payment in the Disputed state (file a
dispute as the buyer first); the seeded disputes 5 and 6 are already settled.

### Automated resolver

The manual `resolve` above is also available as a hands-off internal service. With
`ATTESTOR_AUTO_RESOLVE=true` (and the attestor enabled), a background worker settles
disputes that are due, reproducing the escrow's own precondition:

```
status == Disputed && (attType != 0 || now >= filedAt + resolveDelay)
```

so attested disputes settle promptly and un-attested ones settle once `resolveDelay`
elapses (the policy default then applies). It confirms readiness against the live chain
per payment before sending, never decides the verdict (the onchain PolicyEngine does,
R2/R4), and logs every settlement (R8). It is off by default so it never surprise-settles
a rehearsal. Attestation stays an external input (the delivery fact); the worker only
picks the moment a settlement is already due.

## Evidence store

Content-addressed blob store on the filesystem (`EVIDENCE_DIR`, default
`./evidence-store`). A blob's id is its keccak256 hash, which is exactly the value a
buyer pins on-chain as `EvidenceItem.hash` in `fileDispute`, so the escrow's
`evidenceRoot` commits to precisely what this store holds and anyone can re-verify a
blob by rehashing it. Evidence is user data, kept off the disposable indexer projection.

Uploads are buyer-authorized (see Authentication): the POST carries a signed
`X-Recourse-Auth` header, so a raw curl is impractical. `engine/scripts/open-dispute.mjs`
does the signing. Fetching a blob is a public read.

```
# fetch is public
curl localhost:8080/api/evidence/0x<hash> --output out.jpg
```

## Evidence manifest

The escrow stores only the folded `evidenceRoot`; the ordered `(evType, hash)` list is
calldata, never state, so it lives off-chain here. A manifest is only ever persisted
after its fold is checked against the chain:

```
root = 0; for each item: root = keccak256(abi.encodePacked(root, evType, hash))
```

`POST /api/evidence/manifest` recomputes this fold and reads the payment's live
`evidenceRoot` straight from the escrow (not the projection, so there is no indexer lag);
it stores the list only on an exact match and returns `422` otherwise. `GET
/api/payments/{id}/evidence` re-folds the stored list and re-checks it against the chain
on every read, so a manifest tampered on disk is caught, not trusted. The fold is
golden-tested against `cast keccak` vectors, so a drift from the contract fails `cargo
test`. Manifests are keyed by deployment (`chainId_escrow`) because paymentIds restart at
1 on a fresh escrow.

```
# after fileDispute pins the evidence, record the list (order must match the calldata)
curl -X POST localhost:8080/api/evidence/manifest -H 'content-type: application/json' \
  -d '{"paymentId":10,"items":[{"evType":1,"hash":"0x.."},{"evType":2,"hash":"0x.."}]}'
curl localhost:8080/api/payments/10/evidence
```

`engine/scripts/open-dispute.mjs` exercises the whole chain on Arc: it uploads evidence,
pins it in `fileDispute`, then posts the manifest and prints whether it verified.

## Not here yet

Surfacing evidence on the web verifier, where the browser itself re-folds the list
against the chain root. The web verifier and policy reads stay chain-direct on purpose,
so they remain independently verifiable without trusting this service.
