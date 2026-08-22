#!/usr/bin/env bash
# Runs the attestor and its evidence host as the one process that gets deployed.
#
#   ops/attestor-service.sh              # host plus daemon, against Arc
#   ops/attestor-service.sh --host-only  # serve evidence, do not attest
#
# This is what Dockerfile.attestor runs in production; running it here exercises the
# same entry point. Config comes from deployments/arc-testnet-agent.json. The signing
# key is read from ATTESTOR_KEY and is never logged.
#
# The entry point is TypeScript and node cannot resolve the engine's extensionless
# imports, so it is bundled first. esbuild is already present as a vitest dependency.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export ATTESTOR_RPC="${ATTESTOR_RPC:-https://arc-testnet.drpc.org}"
export ATTESTOR_DEPLOYMENT="${ATTESTOR_DEPLOYMENT:-$ROOT/deployments/arc-testnet-agent.json}"
export EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/.evidence-store}"
export PORT="${PORT:-8787}"

if [ -z "${ATTESTOR_KEY:-}" ]; then
  # anvil account #2, which the demo names as the policy attestor on Arc. A public
  # key on a testnet guards nothing; override ATTESTOR_KEY for anything else.
  export ATTESTOR_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
fi

cd "$ROOT/engine"
mkdir -p dist
npx esbuild scripts/attestor-service.ts --bundle --platform=node --format=esm --outfile=dist/attestor-service.mjs --log-level=warning
exec node dist/attestor-service.mjs "$@"
