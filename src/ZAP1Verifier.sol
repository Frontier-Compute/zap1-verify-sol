// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BLAKE2b} from "./BLAKE2b.sol";

/// @title ZAP1 Merkle Proof Verifier
/// @author zk_nd3r
/// @notice Verifies ZAP1 attestation proofs on-chain. Proofs anchor Zcash
///         shielded memo commitments to an EVM-accessible verification surface.
/// @dev Uses EIP-152 BLAKE2b precompile for gas-efficient hashing.
///      Personalization constants match the deployed ZAP1 protocol (v3.0.0).
contract ZAP1Verifier {
    using BLAKE2b for bytes;

    bytes public constant LEAF_PERSONALIZATION = "NordicShield_";
    bytes public constant NODE_PERSONALIZATION = "NordicShield_MRK";

    /// @notice Emitted when a proof is verified on-chain
    event ProofVerified(
        bytes32 indexed leafHash,
        bytes32 indexed root,
        address indexed verifier
    );

    /// @notice Registered Zcash anchor roots. Operator submits roots after
    ///         confirming the anchor transaction on Zcash mainnet.
    mapping(bytes32 => AnchorRecord) public anchors;

    /// @notice Anchor metadata
    struct AnchorRecord {
        uint64 zcashHeight;    // Zcash block height where anchor tx was mined
        uint64 registeredAt;   // Block timestamp when registered on this chain
        address registeredBy;  // Operator who registered the anchor
        bool exists;
    }

    /// @notice Owner (operator) who can register anchors
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Register a Zcash anchor root. Called by the operator after
    ///         confirming the anchor transaction on Zcash mainnet.
    /// @param root The Merkle root that was anchored
    /// @param zcashHeight The Zcash block height of the anchor transaction
    function registerAnchor(bytes32 root, uint64 zcashHeight) external onlyOwner {
        require(!anchors[root].exists, "anchor already registered");
        anchors[root] = AnchorRecord({
            zcashHeight: zcashHeight,
            registeredAt: uint64(block.timestamp),
            registeredBy: msg.sender,
            exists: true
        });
    }

    /// @notice Verify a ZAP1 Merkle proof against a registered anchor root.
    /// @param leafHash The leaf hash to verify
    /// @param siblings Ordered sibling hashes for the proof path
    /// @param positions Bit array: 0 = leaf is left, 1 = leaf is right for each level
    /// @param expectedRoot The Merkle root the proof should resolve to
    /// @return valid True if the proof is mathematically valid AND the root is registered
    function verifyProof(
        bytes32 leafHash,
        bytes32[] calldata siblings,
        uint256 positions,
        bytes32 expectedRoot
    ) external returns (bool valid) {
        require(siblings.length <= 32, "proof too deep");

        bytes32 current = leafHash;

        for (uint256 i = 0; i < siblings.length; i++) {
            bytes memory input;
            if ((positions >> i) & 1 == 0) {
                // Current node is on the left
                input = abi.encodePacked(current, siblings[i]);
            } else {
                // Current node is on the right
                input = abi.encodePacked(siblings[i], current);
            }
            current = BLAKE2b.hash(NODE_PERSONALIZATION, input);
        }

        valid = (current == expectedRoot) && anchors[expectedRoot].exists;

        if (valid) {
            emit ProofVerified(leafHash, expectedRoot, msg.sender);
        }
    }

    /// @notice Verify a proof without requiring anchor registration (stateless).
    ///         Use this when the caller handles root trust externally.
    /// @param leafHash The leaf hash to verify
    /// @param siblings Ordered sibling hashes
    /// @param positions Bit array for sibling positions
    /// @param expectedRoot The expected Merkle root
    /// @return valid True if the proof path resolves to expectedRoot
    function verifyProofStateless(
        bytes32 leafHash,
        bytes32[] calldata siblings,
        uint256 positions,
        bytes32 expectedRoot
    ) external view returns (bool valid) {
        require(siblings.length <= 32, "proof too deep");

        bytes32 current = leafHash;

        for (uint256 i = 0; i < siblings.length; i++) {
            bytes memory input;
            if ((positions >> i) & 1 == 0) {
                input = abi.encodePacked(current, siblings[i]);
            } else {
                input = abi.encodePacked(siblings[i], current);
            }
            current = BLAKE2b.hash(NODE_PERSONALIZATION, input);
        }

        valid = (current == expectedRoot);
    }

    /// @notice Compute a ZAP1 leaf hash on-chain. Useful for creating
    ///         attestations that bridge from EVM to Zcash verification.
    /// @param payload The pre-constructed leaf payload (type byte + fields)
    /// @return leafHash The BLAKE2b-256 hash with ZAP1 leaf personalization
    function computeLeafHash(bytes calldata payload) external view returns (bytes32) {
        return BLAKE2b.hash(LEAF_PERSONALIZATION, payload);
    }

    /// @notice Check if a root has been registered as a Zcash anchor
    /// @param root The Merkle root to check
    /// @return exists True if the root is registered
    /// @return zcashHeight The Zcash block height (0 if not registered)
    function isAnchorRegistered(bytes32 root) external view returns (bool exists, uint64 zcashHeight) {
        AnchorRecord storage a = anchors[root];
        return (a.exists, a.zcashHeight);
    }

    /// @notice Transfer ownership to a new operator
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
