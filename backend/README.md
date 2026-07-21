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

The indexer polls Arc every `INDEX_INTERVAL_SECS` (default 15), reading every
payment and policy into Postgres and pulling each disputed payment's verdict from
the contract's `previewVerdict`.

## Endpoints

| Method | Path | Returns |
|---|---|---|
| GET | `/health` | status, chainId, indexedPayments |
| GET | `/api/payments` | all payments (optional `?merchant=0x...`) |
| GET | `/api/payments/{id}` | one payment with its verdict |
| GET | `/api/disputes` | payments with a filed claim |
| GET | `/api/policies` | all indexed policies |
| GET | `/api/policies/{id}` | one policy with its rules and hash |
| POST | `/api/demo/attest` | DEMO_MODE: sign a delivery attestation and submit it |
| POST | `/api/demo/resolve` | DEMO_MODE: settle a disputed payment (moves funds) |

Amounts are USDC (6 decimals) as decimal strings. Addresses are lowercased.

## Attestor bot (demo)

The attestor signs one objective fact, delivery status, and pushes the transaction
(R4: no business logic; the onchain PolicyEngine computes the verdict, the attestor
never decides it). It is enabled only when `DEMO_MODE=true` and `ATTESTOR_PK` is set
to the escrow's attestor key (R6, R7). The signing is byte-verified against the
deployed contract: `cargo test` asserts the local EIP-712 digest equals the escrow's
`attestationDigest`, so a produced signature is accepted onchain.

```
# value: 1 DELIVERED, 2 NOT_DELIVERED. Payment must be in the Disputed state.
curl -X POST localhost:8080/api/demo/attest  -H 'content-type: application/json' -d '{"paymentId":7,"value":2}'
curl -X POST localhost:8080/api/demo/resolve -H 'content-type: application/json' -d '{"paymentId":7}'
```

`attest` moves no funds (it only stores the attested value). `resolve` settles and
moves USDC, so verify it against a real node before a live run (R13) and log demo
runs (R8). To exercise the loop you need a payment in the Disputed state (file a
dispute as the buyer first); the seeded disputes 5 and 6 are already settled.

## Not here yet

The evidence blob store is the remaining backend piece. The web verifier and policy
reads stay chain-direct on purpose, so they remain independently verifiable without
trusting this service.
