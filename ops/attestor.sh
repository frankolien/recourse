#!/usr/bin/env bash
# Runs the attestor against Arc testnet. Pass --once for a single sweep.
#
#   ops/attestor.sh --once
#   ops/attestor.sh              # polls until interrupted
#
# Config comes from deployments/arc-testnet-agent.json. The signing key is read
# from ATTESTOR_KEY, or from backend/.env when that is unset, and is never logged.
#
# The entry point is TypeScript and node cannot resolve the engine's extensionless
# imports, so it is bundled first. esbuild is already present as a vitest dependency.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/deployments/arc-testnet-agent.json"
jqf() { python3 -c "import json;print(json.load(open('$DEPLOY'))['$1'])"; }

export ATTESTOR_RPC="${ATTESTOR_RPC:-https://arc-testnet.drpc.org}"
export ATTESTOR_CHAIN_ID="${ATTESTOR_CHAIN_ID:-$(jqf chainId)}"
export ATTESTOR_ESCROW="${ATTESTOR_ESCROW:-$(jqf escrow)}"
export ATTESTOR_EVIDENCE_URL="${ATTESTOR_EVIDENCE_URL:-http://127.0.0.1:8787}"

if [ -z "${ATTESTOR_KEY:-}" ]; then
  # anvil account #2, which the demo names as the policy attestor on Arc. A public
  # key on a testnet guards nothing; override ATTESTOR_KEY for anything else.
  export ATTESTOR_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
fi

cd "$ROOT/engine"
mkdir -p dist
npx esbuild scripts/attestor.ts --bundle --platform=node --format=esm --packages=external --outfile=dist/attestor.mjs --log-level=warning
exec node dist/attestor.mjs "$@"
