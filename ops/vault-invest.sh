#!/usr/bin/env bash
# Puts the settlement vault's spare cash into USYC, and proves it landed.
#
#   ops/vault-invest.sh          keep 20 percent in cash
#   ops/vault-invest.sh 1500     keep 15 percent
#
# Two steps, because either alone does nothing useful. The buffer was set to 10000 on
# 2026-09-12 to unbrick the vault while USYC was refusing it, and at 10000 invest()
# computes a target of zero and moves nothing however much permission we have.
#
# The check at the end is the point. invest() wraps the teller in try/catch and emits
# InvestRefused rather than reverting, so a successful receipt says nothing at all about
# whether the money moved. This is the same shape of lie that made the deposit sweeper
# look healthy for a week. Balances are the only honest answer.
#
# The key is the vault's owner, read from backend/.env, and is never printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/bin:/usr/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/.foundry/bin:$PATH"

BUFFER="${1:-2000}"
RPC="${ARC_RPC_URL:-https://arc-testnet.drpc.org}"
VAULT=0xD7bA758a1a96DbeD42bDbE9a24c2faa3093745e8
TELLER=0x9fdF14c5B14173D74C08Af27AebFf39240dC105A
USYC=0xe9185F0c5F296Ed1797AaE4238D26CCaBEadb86C
AUTH=0xCC205224862C7641930c87679E98999d23C26113
USDC=0x3600000000000000000000000000000000000000

[ "$BUFFER" -ge 0 ] 2>/dev/null && [ "$BUFFER" -le 10000 ] || { echo "buffer must be 0 to 10000"; exit 1; }

KEY="$(grep -E '^ATTESTOR_PK=' "$ROOT/backend/.env" | cut -d= -f2- | tr -d '"'"'"' ')"
[ -n "$KEY" ] || { echo "ATTESTOR_PK not found in backend/.env"; exit 1; }

money() { echo "scale=6; $1 / 1000000" | bc; }
read_call() { cast call "$1" "$2" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}'; }

# Permission first. Without it the invest below fails silently into InvestRefused, and
# the run would look like a buffer problem rather than an allowlist one.
DEP=$(cast sig "deposit(uint256,address)")
CAN=$(cast call $AUTH "canCall(address,address,bytes4)(bool)" $VAULT $TELLER "$DEP" --rpc-url "$RPC" 2>/dev/null || echo "false")
echo "USYC allows this vault to deposit: $CAN"
if [ "$CAN" != "true" ]; then
  echo "Not allowlisted, so investing would be refused and swallowed. Stopping."
  exit 1
fi

echo
echo "Before:"
echo "  bufferBps      $(read_call $VAULT 'bufferBps()(uint256)')"
echo "  cash           $(money "$(cast call $USDC 'balanceOf(address)(uint256)' $VAULT --rpc-url "$RPC" | awk '{print $1}')") USDC"
echo "  investedAssets $(money "$(read_call $VAULT 'investedAssets()(uint256)')") USDC"
echo "  totalAssets    $(money "$(read_call $VAULT 'totalAssets()(uint256)')") USDC"

echo
echo "Setting the buffer to $BUFFER bps"
cast send $VAULT "setBufferBps(uint16)" "$BUFFER" \
  --rpc-url "$RPC" --private-key "$KEY" >/dev/null
echo "Investing"
cast send $VAULT "invest()" \
  --rpc-url "$RPC" --private-key "$KEY" >/dev/null

INVESTED=$(read_call $VAULT 'investedAssets()(uint256)')
SHARES=$(cast call $USYC 'balanceOf(address)(uint256)' $VAULT --rpc-url "$RPC" | awk '{print $1}')

echo
echo "After:"
echo "  bufferBps      $(read_call $VAULT 'bufferBps()(uint256)')"
echo "  cash           $(money "$(cast call $USDC 'balanceOf(address)(uint256)' $VAULT --rpc-url "$RPC" | awk '{print $1}')") USDC"
echo "  investedAssets $(money "$INVESTED") USDC"
echo "  USYC shares    $SHARES"
echo "  totalAssets    $(money "$(read_call $VAULT 'totalAssets()(uint256)')") USDC"

echo
if [ "$INVESTED" = "0" ] || [ -z "$INVESTED" ]; then
  echo "The money did not move. The transaction will still have succeeded, because"
  echo "invest() catches a refusing teller and emits InvestRefused. Check the logs of"
  echo "the invest transaction for that event before assuming a buffer problem."
  exit 1
fi
echo "Invested. Earn will now say the dollars sit in USYC, because it reads this number."
