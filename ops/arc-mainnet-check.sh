#!/bin/zsh
# Arc mainnet readiness. Run it on 16 September 2026, when chain 5042 opens.
#
# It deploys nothing and signs nothing. The rule for mainnet day is that no contract
# holding anyone's money goes up before the audit, so the only question this answers is
# whether the chain has the pieces the account architecture stands on, and whether they
# are the same bytecode as the ones proved on testnet.
#
# Three of those pieces are other people's and canonical, so identical bytecode is the
# check that matters: the deterministic CREATE2 deployer, EntryPoint v0.7, and Safe
# 1.4.1 with its 4337 module. The hashes below were read off Arc testnet on 2026-09-12.
#
# Our own four are pure functions of a salt and their creation code, so they land at the
# same addresses on any chain with that deployer. Finding them absent is expected and
# fine; finding them present with our hash means someone already deployed the identical
# code, which is also fine. Finding a different hash at those addresses is the one
# answer that would stop everything.
set -u
export PATH="/bin:/usr/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/.foundry/bin:$PATH"

RPC="${ARC_MAINNET_RPC:-https://rpc.arc.network}"
EXPECTED_CHAIN=5042
FAILED=0

echo "Arc mainnet check, $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "RPC $RPC"
echo

CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null || echo "")
if [ -z "$CHAIN" ]; then
  echo "The RPC does not answer. Arc mainnet opens 16 September; set ARC_MAINNET_RPC if the"
  echo "endpoint is not the one guessed above."
  exit 1
fi
if [ "$CHAIN" != "$EXPECTED_CHAIN" ]; then
  echo "Wrong chain: the RPC says $CHAIN, this script is for $EXPECTED_CHAIN."
  exit 1
fi
echo "chain $CHAIN, head $(cast block-number --rpc-url "$RPC")"
echo

echo "Canonical pieces, which must be present and byte for byte the ones testnet proved:"
while read -r NAME ADDRESS EXPECTED; do
  [ -z "$NAME" ] && continue
  CODE=$(cast code "$ADDRESS" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" = "0x" ] || [ -z "$CODE" ]; then
    printf "  %-22s MISSING   %s\n" "$NAME" "$ADDRESS"
    FAILED=1
    continue
  fi
  ACTUAL=$(cast keccak "$CODE")
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    printf "  %-22s ok        %s\n" "$NAME" "$ADDRESS"
  else
    printf "  %-22s DIFFERENT %s\n" "$NAME" "$ADDRESS"
    printf "  %-22s           testnet %s\n" "" "$EXPECTED"
    printf "  %-22s           mainnet %s\n" "" "$ACTUAL"
    FAILED=1
  fi
done <<'EOF'
create2Deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C 0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989
entryPointV07 0x0000000071727De22E5E9d8BAf0edAc6f37da032 0x8db5ff695839d655407cc8490bb7a5d82337a86a6b39c3f0258aa6c3b582fc58
safe.singleton 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762 0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff
safe.proxyFactory 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67 0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317
safe.module4337 0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226 0x2aea997c4e3cf0e2f333025372e219abcfde81c21fc2f8fb066414a5685dd3e0
safe.moduleSetup 0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47 0xaf2d170bb766d2773c3fa88717f5b3599827478074d3767d1dee55e5c2f3fbcb
EOF

echo
echo "Ours, which should be absent until they are deployed deliberately:"
while read -r NAME ADDRESS EXPECTED; do
  [ -z "$NAME" ] && continue
  CODE=$(cast code "$ADDRESS" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" = "0x" ] || [ -z "$CODE" ]; then
    printf "  %-22s free      %s\n" "$NAME" "$ADDRESS"
    continue
  fi
  ACTUAL=$(cast keccak "$CODE")
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    printf "  %-22s already ours, same code\n" "$NAME"
  else
    printf "  %-22s OCCUPIED by other code, stop and work out why\n" "$NAME"
    FAILED=1
  fi
done <<'EOF'
olien.verifier 0xE196558Ce080229B256dDE6e62CDA2B051B882fC 0xe41738bb73343ceee06a521cc23c8e189f2ed47126eade22bdd0c1257ee95b6f
olien.subAccount 0xDfc576536187eF72689c514f8c7ea6487960a637 0x4290a97245250de75b279290a9f5009115e5861e8d3f0a85e21c55098258c818
olien.implementation 0x8BFf8CCe4edbE882a21197D3942978CCd06fA427 0x7d546243e9c3e421834ed83525c19845c333664ec6128b86abbc3f4b8679b9fc
olien.factory 0xaF8c108D09E6A159D4dcE0919Ca6A81d6019f131 0x39b4f3ea2723b5cec45c3a114036fba72f5f745b81a6012ca797574d4fb69f6b
p256OwnerFactory 0xBb27F2339a48aE263527b3F2DD871ec12a7E7ce8 0xe3df416f13b656de49c3b08f8672dc4c7b8d3924f3a0442310b180cf625e6faf
EOF

echo
echo "The dollar itself:"
USDC=0x3600000000000000000000000000000000000000
SYMBOL=$(cast call $USDC "symbol()(string)" --rpc-url "$RPC" 2>/dev/null || echo "unreadable")
DECIMALS=$(cast call $USDC "decimals()(uint8)" --rpc-url "$RPC" 2>/dev/null || echo "?")
echo "  $USDC answers $SYMBOL with $DECIMALS decimals"

echo
echo "A deployment file to save as deployments/arc-mainnet.json once the four above are"
echo "deployed. The FX router and EURC are left out on purpose: Circle publishes no EURC"
echo "on Arc mainnet, and our own pool is testnet scaffolding that should never be funded"
echo "with real money. No router in the file means the app shows no Convert at all."
cat <<'EOF'
  {
    "chainId": 5042,
    "usdc": "0x3600000000000000000000000000000000000000",
    "safe": {
      "entryPoint": "0x0000000071727De22E5E9d8BAf0edAc6f37da032",
      "module4337": "0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226",
      "moduleSetup": "0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47",
      "proxyFactory": "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67",
      "singleton": "0x29fcB43b46531BcA003ddC8FCB67FFE91900C762"
    }
  }
EOF

echo
if [ "$FAILED" -eq 0 ]; then
  echo "Ready. Nothing was deployed, which is the point."
else
  echo "Not ready. Something above is missing or is not the code testnet proved."
fi
exit $FAILED
