#!/usr/bin/env bash
# The same demo as ops/agent-demo.sh, against Arc testnet instead of anvil.
#
#   ops/agent-demo-arc.sh
#
# Takes about three minutes: scenario A waits out the real dispute window rather
# than warping past it. Spends roughly 0.4 USDC of testnet funds per run, most of
# which comes back.
#
# Reuses the escrow and policy in deployments/arc-testnet-agent.json, which is
# deliberately separate from arc-testnet.json so the app's escrow is untouched.
# Unset DEMO_ESCROW and DEMO_POLICY_ID to deploy a fresh pair instead.
#
# The deployer key is read from backend/.env and never printed. The buyer and
# attestor are well known anvil keys: on a testnet they guard nothing, and using
# them creates no new secret. Note anvil account #1 is blacklisted on Arc USDC,
# which is why the buyer here is #5.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$(python3 -c "import json;print(json.load(open('$ROOT/deployments/arc-testnet-agent.json')))" >/dev/null 2>&1 && echo ok || echo bad)"
[ "$D" = ok ] || { echo "deployments/arc-testnet-agent.json is missing or invalid"; exit 1; }

jqf() { python3 -c "import json,sys;print(json.load(open('$ROOT/deployments/arc-testnet-agent.json'))['$1'])"; }

PK="$(grep '^ATTESTOR_PK=' "$ROOT/backend/.env" | cut -d= -f2)"
[ -n "$PK" ] || { echo "ATTESTOR_PK not found in backend/.env"; exit 1; }

cd "$ROOT/engine"
DEMO_RPC="${DEMO_RPC:-https://arc-testnet.drpc.org}" \
DEMO_CHAIN_ID=5042002 \
DEMO_USDC="$(jqf usdc)" \
DEMO_REGISTRY="$(jqf policyRegistry)" \
DEMO_ADAPTER="$(jqf yieldAdapter)" \
DEMO_ESCROW="${DEMO_ESCROW-$(jqf escrow)}" \
DEMO_POLICY_ID="${DEMO_POLICY_ID-$(jqf agentPolicyId)}" \
DEMO_BUYER_PK=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba \
DEMO_DEPLOYER_PK="$PK" \
npx vitest run test/agent-demo.test.ts --reporter=basic
