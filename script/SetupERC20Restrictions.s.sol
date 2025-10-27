// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TargetRegistry} from "../src/TargetRegistry.sol";

/**
 * @title SetupERC20Restrictions
 * @notice Setup ERC20 transfer restrictions for USDC
 * @dev Run after whitelist setup with: forge script script/SetupERC20Restrictions.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract SetupERC20Restrictions is Script {
    // Base network USDC address
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address registryAddress = vm.envAddress("TARGET_REGISTRY");
        
        console.log("Setting up ERC20 restrictions with account:", deployer);
        console.log("TargetRegistry address:", registryAddress);
        
        TargetRegistry registry = TargetRegistry(registryAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Add USDC as restricted ERC20 token
        console.log("\n=== Setting up USDC Transfer Restrictions ===");
        console.log("Adding USDC as restricted ERC20 token...");
        
        registry.addRestrictedERC20Token(USDC);
        
        console.log("USDC transfer restrictions enabled");
        console.log("USDC transfers will only be allowed to:");
        console.log("- The smart wallet itself");
        console.log("- Smart wallet owners (via getOwners())");
        
        vm.stopBroadcast();
        
        console.log("\n=== ERC20 Restrictions Setup Complete ===");
        console.log("USDC transfers are now restricted to authorized recipients only");
    }
}
