// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AgentPassRegistry} from "../src/AgentPassRegistry.sol";
import {AgentPassVerifier} from "../src/AgentPassVerifier.sol";

/// @title Deploy
/// @notice Foundry deployment script for AgentPassRegistry and AgentPassVerifier.
/// @dev Run with:
///      forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
///      Requires the PRIVATE_KEY environment variable to be set.
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AgentPassRegistry registry = new AgentPassRegistry();
        AgentPassVerifier verifier = new AgentPassVerifier(address(registry));

        vm.stopBroadcast();

        // Log deployed addresses for easy copy-paste into deployments.json.
        console.log("AgentPassRegistry deployed at:", address(registry));
        console.log("AgentPassVerifier deployed at:", address(verifier));
    }
}
