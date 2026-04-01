// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BLAKE2b-256 with personalization support via EIP-152 precompile
/// @author zk_nd3r
/// @notice Uses the BLAKE2b-F precompile (address 0x09) for gas-efficient hashing
library BLAKE2b {
    address constant PRECOMPILE = address(0x09);

    /// @notice Compute BLAKE2b-256 of `input` with `personalization` (up to 16 bytes).
    /// @param personalization The personalization string (padded to 16 bytes)
    /// @param input The data to hash
    /// @return digest The 32-byte BLAKE2b-256 output
    function hash(
        bytes memory personalization,
        bytes memory input
    ) internal view returns (bytes32 digest) {
        // BLAKE2b-256 initialization vector (first 4 words of BLAKE2b IV)
        // Modified by parameter block: digest length = 32, fanout = 1, depth = 1
        uint64[8] memory h;
        h[0] = 0x6a09e667f3bcc908 ^ 0x01010020; // IV[0] XOR (fanout=1 | depth=1 | digestLen=32)
        h[1] = 0xbb67ae8584caa73b;
        h[2] = 0x3c6ef372fe94f82b;
        h[3] = 0xa54ff53a5f1d36f1;
        h[4] = 0x510e527fade682d1;
        h[5] = 0x9b05688c2b3e6c1f;
        h[6] = 0x1f83d9abfb41bd6b;
        h[7] = 0x5be0cd19137e2179;

        // XOR personalization into h[6] and h[7] (parameter block bytes 48-63)
        if (personalization.length > 0) {
            uint64 p0;
            uint64 p1;
            // Pack personalization bytes into two uint64 (little-endian)
            for (uint256 i = 0; i < personalization.length && i < 8; i++) {
                p0 |= uint64(uint8(personalization[i])) << (i * 8);
            }
            for (uint256 i = 8; i < personalization.length && i < 16; i++) {
                p1 |= uint64(uint8(personalization[i])) << ((i - 8) * 8);
            }
            h[6] ^= p0;
            h[7] ^= p1;
        }

        // Process input in 128-byte blocks
        uint256 bytesCompressed = 0;
        uint256 totalLen = input.length;
        uint256 numBlocks = (totalLen + 127) / 128;
        if (numBlocks == 0) numBlocks = 1; // At least one block for empty input

        for (uint256 blockIdx = 0; blockIdx < numBlocks; blockIdx++) {
            // Build 128-byte message block (zero-padded if last)
            uint64[16] memory m;
            uint256 blockStart = blockIdx * 128;
            for (uint256 w = 0; w < 16; w++) {
                uint64 word = 0;
                for (uint256 b = 0; b < 8; b++) {
                    uint256 pos = blockStart + w * 8 + b;
                    if (pos < totalLen) {
                        word |= uint64(uint8(input[pos])) << (b * 8);
                    }
                }
                m[w] = word;
            }

            bytesCompressed += 128;
            if (bytesCompressed > totalLen) {
                bytesCompressed = totalLen;
            }

            bool isFinal = (blockIdx == numBlocks - 1);

            // Call EIP-152 precompile
            h = compress(h, m, uint64(bytesCompressed), 0, isFinal);
        }

        // Extract first 32 bytes (4 words) as little-endian digest
        digest = bytes32(
            (uint256(reverseBytes8(h[0])) << 192) |
            (uint256(reverseBytes8(h[1])) << 128) |
            (uint256(reverseBytes8(h[2])) << 64) |
            uint256(reverseBytes8(h[3]))
        );
    }

    /// @notice Call the BLAKE2b-F compression function (EIP-152)
    function compress(
        uint64[8] memory h,
        uint64[16] memory m,
        uint64 t0,
        uint64 t1,
        bool f
    ) private view returns (uint64[8] memory) {
        // EIP-152 input format: 4 + 64 + 128 + 16 + 1 = 213 bytes
        // [rounds (4)] [h (64)] [m (128)] [t (16)] [f (1)]
        bytes memory precompileInput = new bytes(213);

        // Rounds = 12 (big-endian uint32)
        precompileInput[0] = 0x00;
        precompileInput[1] = 0x00;
        precompileInput[2] = 0x00;
        precompileInput[3] = 0x0c;

        // h state (64 bytes, little-endian uint64s)
        for (uint256 i = 0; i < 8; i++) {
            uint64 v = h[i];
            for (uint256 b = 0; b < 8; b++) {
                precompileInput[4 + i * 8 + b] = bytes1(uint8(v >> (b * 8)));
            }
        }

        // m message (128 bytes, little-endian uint64s)
        for (uint256 i = 0; i < 16; i++) {
            uint64 v = m[i];
            for (uint256 b = 0; b < 8; b++) {
                precompileInput[68 + i * 8 + b] = bytes1(uint8(v >> (b * 8)));
            }
        }

        // t counter (16 bytes: t0 + t1, little-endian)
        for (uint256 b = 0; b < 8; b++) {
            precompileInput[196 + b] = bytes1(uint8(t0 >> (b * 8)));
            precompileInput[204 + b] = bytes1(uint8(t1 >> (b * 8)));
        }

        // f flag
        precompileInput[212] = f ? bytes1(uint8(1)) : bytes1(uint8(0));

        // Call precompile
        (bool ok, bytes memory result) = PRECOMPILE.staticcall(precompileInput);
        require(ok && result.length == 64, "BLAKE2b-F precompile failed");

        // Parse result back into h
        uint64[8] memory newH;
        for (uint256 i = 0; i < 8; i++) {
            uint64 v = 0;
            for (uint256 b = 0; b < 8; b++) {
                v |= uint64(uint8(result[i * 8 + b])) << (b * 8);
            }
            newH[i] = v;
        }
        return newH;
    }

    /// @notice Reverse bytes of a uint64 (for big-endian output)
    function reverseBytes8(uint64 v) private pure returns (uint64) {
        v = ((v & 0xFF00FF00FF00FF00) >> 8) | ((v & 0x00FF00FF00FF00FF) << 8);
        v = ((v & 0xFFFF0000FFFF0000) >> 16) | ((v & 0x0000FFFF0000FFFF) << 16);
        v = (v >> 32) | (v << 32);
        return v;
    }
}
