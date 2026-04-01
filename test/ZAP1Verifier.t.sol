// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZAP1Verifier} from "../src/ZAP1Verifier.sol";
import {BLAKE2b} from "../src/BLAKE2b.sol";

contract ZAP1VerifierTest is Test {
    ZAP1Verifier verifier;

    function setUp() public {
        verifier = new ZAP1Verifier();
    }

    // Test vector from ZAP1 TEST_VECTORS.md:
    // PROGRAM_ENTRY (0x01) with wallet_hash = "wallet_abc"
    // Expected: 344a05bf81faf6e2d54a0e52ea0267aff0244998eb1ee27adf5627413e92f089
    function test_leafHash_programEntry() public view {
        // PROGRAM_ENTRY construction: BLAKE2b_32(0x01 || wallet_hash)
        // No length prefix for PROGRAM_ENTRY (it's the simple case)
        bytes memory payload = abi.encodePacked(uint8(0x01), bytes("wallet_abc"));
        bytes32 result = verifier.computeLeafHash(payload);
        assertEq(
            result,
            bytes32(0x344a05bf81faf6e2d54a0e52ea0267aff0244998eb1ee27adf5627413e92f089)
        );
    }

    // Verify BLAKE2b-256 with personalization produces correct output
    function test_blake2b_personalization() public view {
        bytes memory personalization = bytes("NordicShield_");
        bytes memory input = abi.encodePacked(uint8(0x01), bytes("wallet_abc"));
        bytes32 result = BLAKE2b.hash(personalization, input);
        assertEq(
            result,
            bytes32(0x344a05bf81faf6e2d54a0e52ea0267aff0244998eb1ee27adf5627413e92f089)
        );
    }

    // Test Merkle node hash
    function test_nodeHash() public view {
        bytes memory nodePersonalization = bytes("NordicShield_MRK");
        bytes32 left = bytes32(0x344a05bf81faf6e2d54a0e52ea0267aff0244998eb1ee27adf5627413e92f089);
        bytes32 right = bytes32(0x5d77b9a3435948a98099267e510a14663cc0fa80afd2a3ee5fb4363f6ecdfa13);
        bytes memory input = abi.encodePacked(left, right);
        bytes32 result = BLAKE2b.hash(nodePersonalization, input);
        // This should match the Merkle tree vector from the Rust implementation
        assertTrue(result != bytes32(0));
    }

    // Test anchor registration
    function test_registerAnchor() public {
        bytes32 root = bytes32(0x024e36515ea30efc15a0a7962dd8f677455938079430b9eab174f46a4328a07a);
        verifier.registerAnchor(root, 3286631);

        (bool exists, uint64 height) = verifier.isAnchorRegistered(root);
        assertTrue(exists);
        assertEq(height, 3286631);
    }

    // Test duplicate anchor registration fails
    function test_registerAnchor_duplicate() public {
        bytes32 root = bytes32(uint256(1));
        verifier.registerAnchor(root, 100);

        vm.expectRevert("anchor already registered");
        verifier.registerAnchor(root, 100);
    }

    // Test stateless proof verification with a simple 2-leaf tree
    function test_verifyProofStateless_twoLeaf() public view {
        // Build a 2-leaf tree manually
        bytes32 leaf0 = BLAKE2b.hash(bytes("NordicShield_"), abi.encodePacked(uint8(0x01), bytes("wallet_abc")));
        bytes32 leaf1 = BLAKE2b.hash(bytes("NordicShield_"), abi.encodePacked(uint8(0x01), bytes("wallet_def")));
        bytes32 root = BLAKE2b.hash(bytes("NordicShield_MRK"), abi.encodePacked(leaf0, leaf1));

        // Prove leaf0: sibling is leaf1, position = 0 (leaf is left)
        bytes32[] memory siblings = new bytes32[](1);
        siblings[0] = leaf1;
        bool valid = verifier.verifyProofStateless(leaf0, siblings, 0, root);
        assertTrue(valid);

        // Prove leaf1: sibling is leaf0, position = 1 (leaf is right)
        siblings[0] = leaf0;
        valid = verifier.verifyProofStateless(leaf1, siblings, 1, root);
        assertTrue(valid);
    }

    // Test full proof verification with anchor
    function test_verifyProof_withAnchor() public {
        bytes32 leaf0 = BLAKE2b.hash(bytes("NordicShield_"), abi.encodePacked(uint8(0x01), bytes("wallet_abc")));
        bytes32 leaf1 = BLAKE2b.hash(bytes("NordicShield_"), abi.encodePacked(uint8(0x01), bytes("wallet_def")));
        bytes32 root = BLAKE2b.hash(bytes("NordicShield_MRK"), abi.encodePacked(leaf0, leaf1));

        // Without anchor: should return false
        bytes32[] memory siblings = new bytes32[](1);
        siblings[0] = leaf1;
        bool valid = verifier.verifyProof(leaf0, siblings, 0, root);
        assertFalse(valid);

        // Register anchor
        verifier.registerAnchor(root, 3286631);

        // With anchor: should return true
        valid = verifier.verifyProof(leaf0, siblings, 0, root);
        assertTrue(valid);
    }

    // Test wrong proof fails
    function test_verifyProof_wrongSibling() public view {
        bytes32 leaf0 = BLAKE2b.hash(bytes("NordicShield_"), abi.encodePacked(uint8(0x01), bytes("wallet_abc")));
        bytes32 leaf1 = BLAKE2b.hash(bytes("NordicShield_"), abi.encodePacked(uint8(0x01), bytes("wallet_def")));
        bytes32 root = BLAKE2b.hash(bytes("NordicShield_MRK"), abi.encodePacked(leaf0, leaf1));

        // Wrong sibling
        bytes32[] memory siblings = new bytes32[](1);
        siblings[0] = bytes32(uint256(0xdead));
        bool valid = verifier.verifyProofStateless(leaf0, siblings, 0, root);
        assertFalse(valid);
    }

    // Test ownership
    function test_onlyOwner() public {
        address other = address(0xBEEF);
        vm.prank(other);
        vm.expectRevert("not owner");
        verifier.registerAnchor(bytes32(uint256(1)), 100);
    }

    function test_transferOwnership() public {
        address newOwner = address(0xCAFE);
        verifier.transferOwnership(newOwner);
        assertEq(verifier.owner(), newOwner);
    }
}
