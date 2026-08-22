#!/usr/bin/env bash
# Deploys and seeds the testnet FX pool, then proves the wallet would trade against it.
#
#   ops/seed-pool.sh --anvil    dry run on a throwaway node (do this first, R13)
#   ops/seed-pool.sh --live     Arc testnet
#
# Live mode spends real testnet balances and is not reversible: liquidity can be
# withdrawn but the pair stays. The deployer key comes from backend/.env and is
# never printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
MODE="${1:---anvil}"

(cd "$ROOT/contracts" && forge build >/dev/null)

if [ "$MODE" = "--anvil" ]; then
  command -v anvil >/dev/null || { echo "anvil not found"; exit 1; }
  anvil --port 8545 --silent >/dev/null 2>&1 &
  ANVIL_PID=$!
  trap 'kill "$ANVIL_PID" 2>/dev/null || true' EXIT
  for _ in $(seq 1 50); do
    cast block-number --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1 && break
    sleep 0.2
  done
  export SEED_RPC=http://127.0.0.1:8545
  export SEED_CHAIN_ID=31337
  # anvil account #0, deterministic and public.
  export SEED_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
else
  export SEED_RPC="${SEED_RPC:-https://arc-testnet.drpc.org}"
  export SEED_CHAIN_ID=5042002
  export SEED_KEY="$(grep '^ATTESTOR_PK=' "$ROOT/backend/.env" | cut -d= -f2)"
  export SEED_USDC_TOKEN=0x3600000000000000000000000000000000000000
  export SEED_EURC_TOKEN=0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a
  [ -n "$SEED_KEY" ] || { echo "ATTESTOR_PK not found in backend/.env"; exit 1; }
fi

cd "$ROOT/engine"
mkdir -p dist
npx esbuild scripts/seed-pool.ts --bundle --platform=node --format=esm --packages=external \
  --outfile=dist/seed-pool.mjs --log-level=warning
# Not exec: that would replace this shell and drop the trap, leaving anvil running
# and holding the caller's stdout open forever.
node dist/seed-pool.mjs
