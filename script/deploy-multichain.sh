#!/usr/bin/env bash
set -euo pipefail

# Deploy ZAP1Verifier to any EVM chain
# Usage: PRIVATE_KEY=0x... CHAIN=base ./script/deploy-multichain.sh

: "${PRIVATE_KEY:?set PRIVATE_KEY (deployer)}"
: "${CHAIN:?set CHAIN (base, arbitrum, sepolia)}"

case "$CHAIN" in
  base)
    RPC_URL="https://mainnet.base.org"
    CHAIN_ID=8453
    ;;
  arbitrum)
    RPC_URL="https://arb1.arbitrum.io/rpc"
    CHAIN_ID=42161
    ;;
  sepolia)
    RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
    CHAIN_ID=11155111
    ;;
  *)
    echo "Unknown chain: $CHAIN (use base, arbitrum, or sepolia)"
    exit 1
    ;;
esac

echo "Deploying ZAP1Verifier to $CHAIN (chain ID $CHAIN_ID)"
echo "RPC: $RPC_URL"
echo ""

forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  -vvv

echo ""
echo "Done. Update script/deployed-addresses.json with the new address."
echo "Then register anchors:"
echo "  PRIVATE_KEY=... VERIFIER=<addr> RPC_URL=$RPC_URL ./script/register-anchors.sh"
