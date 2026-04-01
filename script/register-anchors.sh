#!/usr/bin/env bash
set -euo pipefail

# Register all 5 Zcash mainnet anchor roots on the Sepolia ZAP1Verifier
# Usage: PRIVATE_KEY=0x... VERIFIER=0x... RPC_URL=https://... ./script/register-anchors.sh

: "${PRIVATE_KEY:?set PRIVATE_KEY}"
: "${VERIFIER:?set VERIFIER address}"
: "${RPC_URL:?set RPC_URL}"

echo "Registering 5 Zcash anchor roots on Sepolia ZAP1Verifier at $VERIFIER"
echo ""

register() {
    local root="$1"
    local height="$2"
    echo "  anchor $height: ${root:0:16}..."
    cast send "$VERIFIER" \
        "registerAnchor(bytes32,uint64)" \
        "0x$root" \
        "$height" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --quiet
}

register "024e36515ea30efc15a0a7962dd8f677455938079430b9eab174f46a4328a07a" 3286631
register "a5b78c57b062f2e632fd40e8fbbdaf59ab7e527b860cf7db2385bc180cbbf362" 3287612
register "437e12dd66cfcb9e0277b231efabd3ebeb1cc8c0e612bb4ee97c04b93c1f1745" 3288022
register "b09b16becc20047cfc5b97673904d3df978355bb851082b3be4f36f68b9eacf1" 3292017
register "308c7df6482f0552ca20cb7e35bac3c511cc88b9b888ace309f9889d8aa6dedf" 3293076

echo ""
echo "Done. Verify with:"
echo "  cast call $VERIFIER 'isAnchorRegistered(bytes32)(bool,uint64)' 0x024e36515ea30efc15a0a7962dd8f677455938079430b9eab174f46a4328a07a --rpc-url $RPC_URL"
