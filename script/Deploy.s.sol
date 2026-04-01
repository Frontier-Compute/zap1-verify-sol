// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ZAP1Verifier} from "../src/ZAP1Verifier.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ZAP1Verifier verifier = new ZAP1Verifier();
        console.log("ZAP1Verifier deployed to:", address(verifier));

        vm.stopBroadcast();
    }
}
