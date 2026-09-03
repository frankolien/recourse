#!/usr/bin/env bash
# A signed cheque cashed on a throwaway anvil node.
#
#   ops/cheque-demo.sh
#
# The R13 run for cheques. The iOS suite proves the app computes the same EIP-712
# digest that cast does; this proves a token accepts a signature over that digest, and
# that the properties the product claims are actually enforced: not bearer, expires,
# voidable, cashable once.
#
# Arc's USDC is a chain precompile no local EVM can execute, so this runs against
# MockEIP3009USDC, which carries the same EIP-712 domain and the same rules.
#
# Nothing here touches Arc or any funded key.
set -euo pipefail

PORT="${PORT:-8545}"
RPC="http://127.0.0.1:${PORT}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

command -v anvil >/dev/null || { echo "anvil not found. Install foundry."; exit 1; }

echo "building contracts"
(cd "$ROOT/contracts" && forge build >/dev/null)

echo "starting anvil on ${PORT}"
anvil --port "$PORT" --silent &
ANVIL_PID=$!
trap 'kill "$ANVIL_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 0.2
done

cd "$ROOT/engine"
# The project's own vitest, not whatever npx resolves: the npx cache can hold a
# different major version whose reporter flags differ.
DEMO_RPC="$RPC" ./node_modules/.bin/vitest run test/cheque.test.ts --reporter=basic
