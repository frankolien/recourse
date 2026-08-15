#!/usr/bin/env bash
# One agent buying inference from another, end to end on a throwaway anvil node.
# Starts the node, runs both scenarios, tears the node down again.
#
#   ops/agent-demo.sh
#
# Nothing here touches Arc or any funded key: anvil's deterministic accounts hold
# fake USDC from a mock token. See docs/agent-settlement.md section A5.
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

# anvil is ready when it answers, which is sooner than any fixed sleep.
for _ in $(seq 1 50); do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

cd "$ROOT/engine"
DEMO_RPC="$RPC" npx vitest run test/agent-demo.test.ts --reporter=basic
