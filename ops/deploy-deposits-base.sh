#!/usr/bin/env bash
# Puts the deposit factory on Base mainnet, which is how money gets into Recourse.
#
#   ops/deploy-deposits-base.sh          simulate, the default
#   ops/deploy-deposits-base.sh --live   broadcast
#
# Until this exists on a chain people already keep dollars on, an Arc mainnet account
# can only be funded by someone who already has Arc mainnet USDC, which is almost
# nobody. Testnet hid this behind a faucet.
#
# The factory is the same address on every chain because it goes through the Arachnid
# CREATE2 deployer with a fixed salt and takes no constructor arguments. That is what
# makes one person's deposit address identical everywhere, and it is why USDC sent to a
# deposit address on a chain we have not reached yet is waiting rather than lost.
#
# Unlike Arc, Base charges gas in ETH. The deploy is about a million gas at roughly
# 0.006 gwei, which is cents, but it is cents of ETH and the Arc USDC cannot pay it.
#
# The key comes from DEPLOY_PK or ATTESTOR_PK in backend/.env and is never printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/bin:/usr/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/.foundry/bin:$PATH"

RPC="${BASE_RPC_URL:-https://mainnet.base.org}"
LIVE=0
for arg in "$@"; do
  case "$arg" in
    --live) LIVE=1 ;;
    *) echo "unknown flag: $arg"; exit 1 ;;
  esac
done

CHAIN=$(cast chain-id --rpc-url "$RPC")
[ "$CHAIN" = "8453" ] || { echo "that RPC is chain $CHAIN, not Base mainnet"; exit 1; }
echo "Base mainnet, chain $CHAIN, head $(cast block-number --rpc-url "$RPC")"

# The deployer has to be there or the address is not what anything predicted.
CREATE2=0x4e59b44847b379578588920cA78FbF26c0B4956C
[ -n "$(cast code $CREATE2 --rpc-url "$RPC" | tr -d '0x')" ] || { echo "no Arachnid CREATE2 deployer on this chain"; exit 1; }
echo "CREATE2 deployer present"

# Circle's own USDC, so a deposit address sweeps the real token rather than a copy.
USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
SYM=$(cast call $USDC "symbol()(string)" --rpc-url "$RPC" 2>/dev/null || echo "unreadable")
echo "USDC at $USDC answers $SYM"

EXPECTED=0x9C24d756781171e8839Ce0a5e37522BE5528FD82
EXISTING=$(cast code $EXPECTED --rpc-url "$RPC" | tr -d '0x')
if [ -n "$EXISTING" ]; then
  echo "the factory is already at $EXPECTED on this chain, so there is nothing to do"
  exit 0
fi
echo "factory address $EXPECTED is free, which is expected"

key_from_env() { grep -E "^$1=" "$ROOT/backend/.env" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ' || true; }
KEY="${DEPLOY_PK:-}"
[ -n "$KEY" ] || KEY="$(key_from_env DEPLOY_PK)"
[ -n "$KEY" ] || KEY="$(key_from_env ATTESTOR_PK)"
[ -n "$KEY" ] || { echo "no deploying key: set DEPLOY_PK, or ATTESTOR_PK in backend/.env"; exit 1; }

DEPLOYER=$(cast wallet address --private-key "$KEY")
BAL=$(cast balance "$DEPLOYER" --rpc-url "$RPC")
echo "deployer $DEPLOYER holds $(python3 -c "print(f'{$BAL/1e18:.8f}')") ETH, which is what pays for gas here"
[ "$BAL" -gt 10000000000000 ] || { echo "that is not enough ETH on Base to deploy; send about 0.002"; exit 1; }

cd "$ROOT/contracts"
if [ "$LIVE" -eq 1 ]; then
  forge script script/DeployDepositFactory.s.sol:DeployDepositFactory \
    --rpc-url "$RPC" --private-key "$KEY" --broadcast
  echo
  echo "Deployed. Confirming what is actually on the chain:"
  echo "  code at $EXPECTED: $(cast code $EXPECTED --rpc-url "$RPC" | head -c 12)..."
  echo "  its usdc():        $(cast call $EXPECTED 'usdc()(address)' --rpc-url "$RPC")"
  echo "  its messenger():   $(cast call $EXPECTED 'messenger()(address)' --rpc-url "$RPC")"
  echo
  echo "Next: set DEPOSIT_FACTORY=$EXPECTED on the backend that serves Arc mainnet."
else
  forge script script/DeployDepositFactory.s.sol:DeployDepositFactory \
    --rpc-url "$RPC" --private-key "$KEY"
  echo
  echo "Simulated only. Nothing was sent."
  echo "It would land at $EXPECTED, the same address it holds on Base Sepolia."
  echo "Add --live to broadcast."
fi
