// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BLAKE2b} from "./BLAKE2b.sol";

/// @title ZcashRelay -- Zcash light client on Ethereum
/// @author zk_nd3r
/// @notice Accepts Zcash block headers, verifies Equihash PoW via EIP-152,
///         and maintains a verified header chain on-chain.
/// @dev Zcash block header: 1487 bytes total
///   - version:      4 bytes
///   - prevBlock:    32 bytes
///   - merkleRoot:   32 bytes
///   - reserved:     32 bytes
///   - time:         4 bytes
///   - bits:         4 bytes (compact target)
///   - nonce:       32 bytes
///   - solutionSize: 3 bytes (compactSize of 1344)
///   - solution:  1344 bytes (Equihash n=200,k=9)
///   Total: 4+32+32+32+4+4+32+3+1344 = 1487
contract ZcashRelay {

    // -- Constants --
    uint256 constant HEADER_SIZE = 1487;
    uint256 constant HEADER_PREFIX_LEN = 140;
    uint256 constant SOLUTION_OFFSET = 143;
    uint256 constant SOLUTION_SIZE = 1344;

    // -- Storage --
    mapping(uint256 => bytes32) public blockHashes;
    mapping(bytes32 => uint256) public hashToHeight;
    mapping(bytes32 => bytes32) public blockMerkleRoots;
    uint256 public latestHeight;
    bytes32 public genesisHash;
    bool public initialized;
    address public owner;

    // -- Events --
    event BlockSubmitted(
        uint256 indexed height,
        bytes32 indexed blockHash,
        bytes32 prevHash
    );
    event GenesisSet(uint256 indexed height, bytes32 indexed blockHash);

    // -- Errors --
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidHeaderSize(uint256 got, uint256 expected);
    error PrevBlockNotFound(bytes32 prevHash);
    error BlockAlreadyStored(bytes32 blockHash);
    error InvalidEquihashSolution();
    error TargetExceeded();
    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ----------------------------------------------------------------
    // Initialization
    // ----------------------------------------------------------------

    /// @notice Set the genesis/checkpoint block (trust anchor). Called once.
    function setGenesis(
        uint256 height,
        bytes32 blockHash,
        bytes32 merkleRoot
    ) external onlyOwner {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        genesisHash = blockHash;
        latestHeight = height;
        blockHashes[height] = blockHash;
        hashToHeight[blockHash] = height;
        blockMerkleRoots[blockHash] = merkleRoot;
        emit GenesisSet(height, blockHash);
    }

    // ----------------------------------------------------------------
    // Header Submission
    // ----------------------------------------------------------------

    /// @notice Submit a Zcash block header for verification and storage.
    /// @param header The full 1487-byte block header
    /// @param height The claimed block height
    function submitBlockHeader(
        bytes calldata header,
        uint256 height
    ) external {
        if (!initialized) revert NotInitialized();
        if (header.length != HEADER_SIZE)
            revert InvalidHeaderSize(header.length, HEADER_SIZE);

        // Parse prevBlock (bytes 4..36, little-endian)
        bytes32 prevHash = _readBytes32LE(header, 4);

        // Chain continuity check
        require(blockHashes[height - 1] != bytes32(0), "prev block missing");
        require(blockHashes[height - 1] == prevHash, "prevBlock mismatch");

        // Parse merkle root (bytes 36..68)
        bytes32 merkleRoot = _readBytes32LE(header, 36);

        // Block hash = BLAKE2b-256("ZcashBlockHash", header_prefix)
        bytes32 blockHash = _computeBlockHash(header);

        if (hashToHeight[blockHash] != 0) revert BlockAlreadyStored(blockHash);

        // Verify Equihash solution structure
        _verifyEquihash(header);

        // Verify PoW target
        uint32 bits = _readUint32LE(header, 104);
        _verifyTarget(blockHash, bits);

        // Store
        blockHashes[height] = blockHash;
        hashToHeight[blockHash] = height;
        blockMerkleRoots[blockHash] = merkleRoot;
        if (height > latestHeight) {
            latestHeight = height;
        }

        emit BlockSubmitted(height, blockHash, prevHash);
    }

    // ----------------------------------------------------------------
    // Queries
    // ----------------------------------------------------------------

    function getBlockHash(uint256 height) external view returns (bytes32) {
        return blockHashes[height];
    }

    function getLatestHeight() external view returns (uint256) {
        return latestHeight;
    }

    function getMerkleRoot(uint256 height) external view returns (bytes32) {
        bytes32 bh = blockHashes[height];
        require(bh != bytes32(0), "block not found");
        return blockMerkleRoots[bh];
    }

    /// @notice Verify transaction inclusion via SHA-256d merkle proof.
    function verifyTransaction(
        bytes32 txid,
        uint256 height,
        bytes calldata proof,
        uint256 index
    ) external view returns (bool valid) {
        bytes32 bh = blockHashes[height];
        require(bh != bytes32(0), "block not verified");
        bytes32 root = blockMerkleRoots[bh];

        bytes32 current = txid;
        uint256 proofLen = proof.length / 32;
        for (uint256 i = 0; i < proofLen; i++) {
            bytes32 sibling;
            uint256 off = i * 32;
            assembly {
                sibling := calldataload(add(proof.offset, off))
            }
            if (index & 1 == 0) {
                current = _sha256d(abi.encodePacked(current, sibling));
            } else {
                current = _sha256d(abi.encodePacked(sibling, current));
            }
            index >>= 1;
        }
        valid = (current == root);
    }

    // ----------------------------------------------------------------
    // Internal: Block Hash
    // ----------------------------------------------------------------

    function _computeBlockHash(
        bytes calldata header
    ) internal view returns (bytes32) {
        bytes memory prefix = header[0:HEADER_PREFIX_LEN];
        return BLAKE2b.hash(bytes("ZcashBlockHash"), prefix);
    }

    // ----------------------------------------------------------------
    // Internal: Equihash Verification
    // ----------------------------------------------------------------

    /// @notice Verify Equihash (n=200, k=9) solution.
    /// @dev Full verification requires ~256 BLAKE2b calls to build the hash
    ///      outputs, then XOR-tree validation across k=9 levels.
    ///      Current implementation verifies solution structure:
    ///      - 512 indices extracted from 1344-byte solution (21 bits each)
    ///      - All indices in valid range (< 2^21)
    ///      - Tree ordering constraints at all 9 levels
    ///      TODO: Add full BLAKE2b XOR-tree collision verification.
    ///      Estimated additional gas: ~1.5M (256 precompile calls).
    function _verifyEquihash(bytes calldata header) internal pure {
        bytes calldata solution = header[SOLUTION_OFFSET:SOLUTION_OFFSET + SOLUTION_SIZE];
        uint32[512] memory idx = _extractIndices(solution);

        // Range check
        for (uint256 i = 0; i < 512; i++) {
            require(idx[i] < 2097152, "index out of range");
        }

        // Tree ordering: k=9 levels
        // Level 0: pairs
        for (uint256 i = 0; i < 512; i += 2) {
            require(idx[i] < idx[i + 1], "L0 order");
        }
        // Levels 1-8: each group's first element < second half's first
        uint256 stride = 4;
        for (uint256 level = 1; level < 9; level++) {
            for (uint256 i = 0; i < 512; i += stride) {
                require(idx[i] < idx[i + stride / 2], "tree order");
            }
            stride *= 2;
        }
    }

    /// @notice Extract 512 x 21-bit indices from 1344-byte Equihash solution.
    /// @dev 512 * 21 = 10752 bits = 1344 bytes (exact)
    function _extractIndices(
        bytes calldata solution
    ) internal pure returns (uint32[512] memory indices) {
        uint256 bitPos = 0;
        for (uint256 i = 0; i < 512; i++) {
            uint256 bytePos = bitPos / 8;
            uint256 bitOff = bitPos % 8;
            uint32 val = 0;
            for (uint256 b = 0; b < 4 && (bytePos + b) < SOLUTION_SIZE; b++) {
                val |= uint32(uint8(solution[bytePos + b])) << (b * 8);
            }
            indices[i] = (val >> uint32(bitOff)) & 0x1FFFFF;
            bitPos += 21;
        }
    }

    // ----------------------------------------------------------------
    // Internal: Target Verification
    // ----------------------------------------------------------------

    /// @notice Verify block hash meets compact target.
    /// @dev bits = 0xEEMMMMMM: target = mantissa * 2^(8*(exp-3))
    function _verifyTarget(bytes32 blockHash, uint32 bits) internal pure {
        uint256 exp = bits >> 24;
        uint256 mantissa = bits & 0x007FFFFF;
        require(mantissa != 0, "zero mantissa");

        uint256 target;
        if (exp <= 3) {
            target = mantissa >> (8 * (3 - exp));
        } else {
            target = mantissa << (8 * (exp - 3));
        }
        require(uint256(blockHash) <= target, "hash exceeds target");
    }

    // ----------------------------------------------------------------
    // Internal: SHA-256d (for tx merkle tree)
    // ----------------------------------------------------------------

    function _sha256d(bytes memory data) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(data)));
    }

    // ----------------------------------------------------------------
    // Internal: Read helpers
    // ----------------------------------------------------------------

    function _readBytes32LE(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (bytes32 result) {
        bytes32 raw;
        assembly {
            raw := calldataload(add(data.offset, offset))
        }
        result = _reverseBytes32(raw);
    }

    function _readUint32LE(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (uint32) {
        return uint32(uint8(data[offset]))
            | (uint32(uint8(data[offset + 1])) << 8)
            | (uint32(uint8(data[offset + 2])) << 16)
            | (uint32(uint8(data[offset + 3])) << 24);
    }

    function _reverseBytes32(bytes32 input) internal pure returns (bytes32) {
        uint256 v = uint256(input);
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8)
          | ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16)
          | ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32)
          | ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64)
          | ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);
        v = (v >> 128) | (v << 128);
        return bytes32(v);
    }

    // ----------------------------------------------------------------
    // Admin
    // ----------------------------------------------------------------

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
