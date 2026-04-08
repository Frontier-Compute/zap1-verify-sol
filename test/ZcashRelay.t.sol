// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZcashRelay} from "../src/ZcashRelay.sol";
import {BLAKE2b} from "../src/BLAKE2b.sol";

contract ZcashRelayTest is Test {
    ZcashRelay relay;

    bytes32 constant GENESIS_HASH = bytes32(uint256(0xaabb));
    bytes32 constant GENESIS_MERKLE = bytes32(uint256(0xccdd));
    uint256 constant GENESIS_HEIGHT = 2800000;

    function setUp() public {
        relay = new ZcashRelay();
        relay.setGenesis(GENESIS_HEIGHT, GENESIS_HASH, GENESIS_MERKLE);
    }

    // -- Initialization tests --

    function test_genesis() public view {
        assertEq(relay.getLatestHeight(), GENESIS_HEIGHT);
        assertEq(relay.getBlockHash(GENESIS_HEIGHT), GENESIS_HASH);
        assertTrue(relay.initialized());
        assertEq(relay.genesisHash(), GENESIS_HASH);
    }

    function test_genesis_double_init_reverts() public {
        vm.expectRevert(ZcashRelay.AlreadyInitialized.selector);
        relay.setGenesis(1, bytes32(uint256(1)), bytes32(uint256(2)));
    }

    function test_genesis_only_owner() public {
        ZcashRelay r2 = new ZcashRelay();
        vm.prank(address(0xBEEF));
        vm.expectRevert(ZcashRelay.NotOwner.selector);
        r2.setGenesis(1, bytes32(uint256(1)), bytes32(uint256(2)));
    }

    // -- Header submission revert tests --

    function test_submit_not_initialized() public {
        ZcashRelay r2 = new ZcashRelay();
        bytes memory header = new bytes(1487);
        vm.expectRevert(ZcashRelay.NotInitialized.selector);
        r2.submitBlockHeader(header, 1);
    }

    function test_submit_wrong_size() public {
        bytes memory header = new bytes(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                ZcashRelay.InvalidHeaderSize.selector,
                100,
                1487
            )
        );
        relay.submitBlockHeader(header, GENESIS_HEIGHT + 1);
    }

    // -- Query tests --

    function test_getBlockHash_missing() public view {
        assertEq(relay.getBlockHash(999), bytes32(0));
    }

    function test_getMerkleRoot() public view {
        bytes32 mr = relay.getMerkleRoot(GENESIS_HEIGHT);
        assertEq(mr, GENESIS_MERKLE);
    }

    function test_getMerkleRoot_missing_reverts() public {
        vm.expectRevert("block not found");
        relay.getMerkleRoot(999);
    }

    // -- BLAKE2b integration --

    function test_blake2b_zcash_personalization() public view {
        // Verify the BLAKE2b library works with Zcash-style personalization
        bytes memory pers = bytes("ZcashBlockHash");
        bytes memory data = new bytes(140); // empty 140-byte header prefix
        bytes32 h = BLAKE2b.hash(pers, data);
        // Should produce a deterministic non-zero hash
        assertTrue(h != bytes32(0));
    }

    function test_blake2b_equihash_personalization() public view {
        // "ZcashPoW" + le32(200) + le32(9) = 16 bytes
        bytes memory pers = new bytes(16);
        pers[0] = 0x5a; // Z
        pers[1] = 0x63; // c
        pers[2] = 0x61; // a
        pers[3] = 0x73; // s
        pers[4] = 0x68; // h
        pers[5] = 0x50; // P
        pers[6] = 0x6f; // o
        pers[7] = 0x57; // W
        pers[8] = 0xc8; // 200
        pers[9] = 0x00;
        pers[10] = 0x00;
        pers[11] = 0x00;
        pers[12] = 0x09; // 9
        pers[13] = 0x00;
        pers[14] = 0x00;
        pers[15] = 0x00;

        bytes memory data = new bytes(144); // header prefix + le32(index)
        bytes32 h = BLAKE2b.hash(pers, data);
        assertTrue(h != bytes32(0));
    }

    // -- Ownership --

    function test_transferOwnership() public {
        address newOwner = address(0xCAFE);
        relay.transferOwnership(newOwner);
        assertEq(relay.owner(), newOwner);
    }

    function test_transferOwnership_zero_reverts() public {
        vm.expectRevert("zero address");
        relay.transferOwnership(address(0));
    }

    // -- SHA-256d transaction verification --

    function test_verifyTransaction_not_verified_reverts() public {
        vm.expectRevert("block not verified");
        relay.verifyTransaction(bytes32(0), 999, "", 0);
    }
}
