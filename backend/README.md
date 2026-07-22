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
