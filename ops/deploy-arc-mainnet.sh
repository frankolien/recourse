#!/usr/bin/env bash
# Puts the one contract Recourse is missing onto Arc mainnet.
#
#   ops/deploy-arc-mainnet.sh          simulate, the default
#   ops/deploy-arc-mainnet.sh --live   broadcast
#
# What is already on chain 5042, read on 2026-09-23 and not assumed: the USDC
# precompile, the whole Safe 1.4.1 stack with EntryPoint v0.7, the Arachnid CREATE2
# deployer, CCTP v2, and the RIP-7212 precompile. Every one of those is someone else's
# and audited. The only piece missing is ours.
#
# That piece is P256OwnerFactory, which turns a Device Key into a Safe owner. It holds
# no money: the Safe does. But it decides who may move the Safe's money, so it is the
# one contract here where a bug costs someone real dollars, and it is unaudited. Deploy
# it, then move your own money first, then a handful of people who know what this is.
#
# The deploying key comes from DEPLOY_PK or ATTESTOR_PK in backend/.env and is never
# printed. Gas on Arc is USDC, so the deployer needs USDC rather than ether.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/bin:/usr/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/.foundry/bin:$PATH"

RPC="${ARC_MAINNET_RPC:-https://rpc.mainnet.arc.io}"
LIVE=0
for arg in "$@"; do
  case "$arg" in
    --live) LIVE=1 ;;
    *) echo "unknown flag: $arg"; exit 1 ;;
  esac
done

# The readiness gate runs first either way. Deploying onto a chain whose EntryPoint is
# not the one the code expects is the failure worth thirty seconds to avoid.
"$ROOT/ops/arc-mainnet-check.sh"

CHAIN=$(cast chain-id --rpc-url "$RPC")
[ "$CHAIN" = "5042" ] || { echo "that RPC is chain $CHAIN, not Arc mainnet"; exit 1; }

# The precompile decides the constructor argument, and the constructor argument decides
# the address, so this is checked rather than trusted. A valid signature must answer 1.
PROBE=$(node "$ROOT/ops/p256-probe.mjs")
ANSWER=$(cast call 0x0000000000000000000000000000000000000100 --data "$PROBE" --rpc-url "$RPC" 2>/dev/null || echo "")
if [ "$ANSWER" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
  echo "the RIP-7212 precompile did not verify a valid signature on this chain."
  echo "Set RECOURSE_P256_FALLBACK to a Solidity verifier before deploying, or every"
  echo "Face ID signature will fail on chain."
  exit 1
fi
echo "P-256 precompile verified a live signature, so no Solidity fallback is wired."

key_from_env() { grep -E "^$1=" "$ROOT/backend/.env" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ' || true; }
KEY="${DEPLOY_PK:-}"
[ -n "$KEY" ] || KEY="$(key_from_env DEPLOY_PK)"
[ -n "$KEY" ] || KEY="$(key_from_env ATTESTOR_PK)"
[ -n "$KEY" ] || { echo "no deploying key: set DEPLOY_PK, or ATTESTOR_PK in backend/.env"; exit 1; }

DEPLOYER=$(cast wallet address --private-key "$KEY")
BAL=$(cast call 0x3600000000000000000000000000000000000000 "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
echo "deployer $DEPLOYER holds $(echo "scale=6; $BAL / 1000000" | bc) USDC, which is what pays for gas here"
[ "$BAL" != "0" ] || { echo "that account has no USDC, so it cannot pay for a transaction on Arc"; exit 1; }

cd "$ROOT/contracts"
if [ "$LIVE" -eq 1 ]; then
  forge script script/DeployP256OwnerFactory.s.sol:DeployP256OwnerFactory \
    --rpc-url "$RPC" --private-key "$KEY" --broadcast
  echo
  echo "Deployed. Reading back what is actually on the chain:"
  FACTORY=$(python3 -c "import json;print(json.load(open('$ROOT/deployments/5042.json'))['p256OwnerFactory'])")
  echo "  deployments/5042.json says $FACTORY"
  echo "  code at that address: $(cast code "$FACTORY" --rpc-url "$RPC" | head -c 12)..."
else
  forge script script/DeployP256OwnerFactory.s.sol:DeployP256OwnerFactory \
    --rpc-url "$RPC" --private-key "$KEY"
  echo
  echo "Simulated only. Nothing was sent and deployments/5042.json was not written."
  echo "It would land at 0xdd7e1afcd4d1e63fc53dfc3ed28faaed22fb6d46, which is free today."
  echo "Add --live to broadcast."
fi
