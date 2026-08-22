#!/usr/bin/env bash
# The demo settled by a separately running attestor, on a throwaway anvil node.
#
#   ops/agent-demo-hosted.sh
#
# This is the anvil dry run for the deployed attestor (R13). Everything else in the
# demo already works with the attestor swept inline; what is verified here is the
# part that only exists in production: the buyer publishes over HTTP to a process it
# does not control, and that process finds the dispute and attests on its own.
#
# Two passes are needed because the attestor has to be told which escrow to watch,
# and the first pass is what deploys it. The second pass reuses everything.
#
# Nothing here touches Arc or any funded key.
set -euo pipefail

PORT="${PORT:-8545}"
EVIDENCE_PORT="${EVIDENCE_PORT:-8787}"
RPC="http://127.0.0.1:${PORT}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

command -v anvil >/dev/null || { echo "anvil not found. Install foundry."; exit 1; }

WORK="$(mktemp -d)"
cleanup() {
  [ -n "${SERVICE_PID:-}" ] && kill "$SERVICE_PID" 2>/dev/null || true
  [ -n "${ANVIL_PID:-}" ] && kill "$ANVIL_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "building contracts"
(cd "$ROOT/contracts" && forge build >/dev/null)

echo "starting anvil on ${PORT}"
anvil --port "$PORT" --silent &
ANVIL_PID=$!
for _ in $(seq 1 50); do
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 0.2
done

cd "$ROOT/engine"

echo
echo "pass 1: deploy, and prove the inline path still works"
DEMO_RPC="$RPC" npx vitest run test/agent-demo.test.ts --reporter=basic | tee "$WORK/pass1.log"

field() { grep -m1 "^  $1 " "$WORK/pass1.log" | awk '{print $2}'; }
ESCROW="$(field escrow)"
REGISTRY="$(field registry)"
ADAPTER="$(field adapter)"
USDC="$(field usdc)"
[ -n "$ESCROW" ] && [ -n "$USDC" ] || { echo "could not read the deployed addresses from pass 1"; exit 1; }

echo
echo "starting the attestor service against ${ESCROW}"
# anvil account #2, the attestor the demo names on its policies.
ATTESTOR_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
ATTESTOR_RPC="$RPC" \
ATTESTOR_CHAIN_ID=31337 \
ATTESTOR_ESCROW="$ESCROW" \
ATTESTOR_INTERVAL_MS=3000 \
EVIDENCE_DIR="$WORK/evidence" \
EVIDENCE_WRITE_TOKEN=anvil-dry-run \
PORT="$EVIDENCE_PORT" \
"$ROOT/ops/attestor-service.sh" > "$WORK/service.log" 2>&1 &
SERVICE_PID=$!

for _ in $(seq 1 60); do
  curl -sf "http://127.0.0.1:${EVIDENCE_PORT}/health" >/dev/null && break
  sleep 0.5
done
curl -sf "http://127.0.0.1:${EVIDENCE_PORT}/health" >/dev/null || {
  echo "the attestor service never became healthy"; cat "$WORK/service.log"; exit 1;
}

echo
echo "pass 2: the same demo, settled by that service instead of an inline sweep"
# A fresh policy, because pass 1's payments are already settled against the old one.
DEMO_RPC="$RPC" \
DEMO_USDC="$USDC" \
DEMO_REGISTRY="$REGISTRY" \
DEMO_ADAPTER="$ADAPTER" \
DEMO_ESCROW="$ESCROW" \
DEMO_EVIDENCE_URL="http://127.0.0.1:${EVIDENCE_PORT}" \
DEMO_EVIDENCE_TOKEN=anvil-dry-run \
DEMO_ATTEST_TIMEOUT_MS=90000 \
npx vitest run test/agent-demo.test.ts --reporter=basic

echo
echo "attestor service log"
sed 's/^/  /' "$WORK/service.log"
