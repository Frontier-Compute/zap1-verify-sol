# zap1-verify-sol

Solidity verifier for ZAP1 Merkle proofs. Verify Zcash shielded attestations on any EVM chain.

## What this does

ZAP1 anchors Merkle roots to Zcash mainnet via shielded memos. This contract verifies those proofs on Ethereum (or any EVM chain), bridging Zcash attestation to EVM-accessible smart contracts. The underlying data stays shielded on Zcash - only the proof is verified on-chain.

Uses the EIP-152 BLAKE2b-F precompile for gas-efficient hashing with ZAP1's domain-separated personalization strings.

## Deployed

| Network | Address | Etherscan |
|---|---|---|
| Sepolia | `0x3fD65055A8dC772C848E7F227CE458803005C87F` | [View](https://sepolia.etherscan.io/address/0x3fD65055A8dC772C848E7F227CE458803005C87F) |

2 Zcash mainnet anchor roots registered. Live demo: [frontiercompute.cash/bridge.html](https://frontiercompute.cash/bridge.html)

## Contracts

- `BLAKE2b.sol` - BLAKE2b-256 with personalization via EIP-152 precompile
- `ZAP1Verifier.sol` - Merkle proof verification + anchor registry

## Usage

### Verify a proof

```solidity
ZAP1Verifier verifier = ZAP1Verifier(DEPLOYED_ADDRESS);

bool valid = verifier.verifyProofStateless(
    leafHash,       // bytes32: the leaf to verify
    siblings,       // bytes32[]: sibling hashes in the proof path
    positions,      // uint256: bit array of sibling positions (0=left, 1=right)
    expectedRoot    // bytes32: the Merkle root
);
```

### With anchor trust

```solidity
// Operator registers a Zcash anchor root
verifier.registerAnchor(root, zcashBlockHeight);

// Anyone can verify a proof against a registered anchor
bool valid = verifier.verifyProof(leafHash, siblings, positions, root);
// Returns true only if proof is valid AND root is registered
```

### Compute a leaf hash on-chain

```solidity
// Build the payload: type byte + fields (matching ZAP1 hash construction rules)
bytes memory payload = abi.encodePacked(uint8(0x01), walletHash);
bytes32 leaf = verifier.computeLeafHash(payload);
```

## Build

Requires [Foundry](https://getfoundry.sh/).

```bash
forge build
forge test
```

## Protocol

- Hash function: BLAKE2b-256 (EIP-152 precompile)
- Leaf personalization: `NordicShield_` (13 bytes)
- Node personalization: `NordicShield_MRK` (16 bytes)
- Spec: [ONCHAIN_PROTOCOL.md](https://github.com/Frontier-Compute/zap1/blob/main/ONCHAIN_PROTOCOL.md)

## License

MIT
