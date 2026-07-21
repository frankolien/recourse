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

Amounts are USDC (6 decimals) as decimal strings. Addresses are lowercased.

## Not here yet

Evidence store and the attestor bot (architecture section 5) are the next
backend pieces. The web verifier and policy reads stay chain-direct on purpose,
so they remain independently verifiable without trusting this service.
