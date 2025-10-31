// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {GuardedExecModuleUpgradeable} from "../src/module/GuardedExecModuleUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TargetRegistry} from "../src/registry/TargetRegistry.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Upgrade and Update Module
 * @notice Upgrade GuardedExecModuleUpgradeable implementation and update registry
 * @dev Run with: forge script script/2-UpgradeAndUpdateModule.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
 * 
 * PREREQUISITES:
 * - Set New TARGET_REGISTRY_ADDRESS env variable
 * - Set PROXY_ADDRESS env variable (existing proxy from previous deployment)
 */
contract UpgradeAndUpdateModule is Script {
    // Existing proxy address (from previous deployment)
    address constant PROXY_ADDRESS = 0x7B3072f06105c08de4997bdC74C7095327fD475c;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get new registry address from env or hardcode
        address newRegistryAddress = vm.envOr("TARGET_REGISTRY_ADDRESS", address(0));
        
        if (newRegistryAddress == address(0)) {
            revert("Please set TARGET_REGISTRY_ADDRESS environment variable");
        }
        
        console.log("=== Upgrading GuardedExecModule ===");
        console.log("Deployer:", deployer);
        console.log("Proxy address:", PROXY_ADDRESS);
        console.log("New registry address:", newRegistryAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy new implementation
        console.log("\n--- Step 1: Deploy new implementation ---");
        GuardedExecModuleUpgradeable newImplementation = new GuardedExecModuleUpgradeable();
        console.log("New implementation deployed to:", address(newImplementation));
        
        // Step 2: Upgrade proxy to new implementation
        console.log("\n--- Step 2: Upgrade proxy to new implementation ---");
        GuardedExecModuleUpgradeable proxy = GuardedExecModuleUpgradeable(PROXY_ADDRESS);
        
        // Verify current owner can upgrade
        require(proxy.owner() == deployer, "Deployer is not the owner");
        console.log("Owner verified:", proxy.owner());
        
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("Proxy upgraded to:", address(newImplementation));
        
        // Step 3: Update registry on proxy
        console.log("\n--- Step 3: Update registry on proxy ---");
        proxy.updateRegistry(newRegistryAddress);
        console.log("Registry updated to:", newRegistryAddress);
        
        vm.stopBroadcast();
        
        // Verify deployment
        console.log("\n=== Verification ===");
        assert(address(proxy.registry()) == newRegistryAddress);
        console.log("Registry verified:", address(proxy.registry()));
        console.log("Owner:", proxy.owner());
        
        console.log("\n=== Deployment Success ===");
        console.log("Proxy address:", PROXY_ADDRESS);
        console.log("New implementation:", address(newImplementation));
        console.log("Updated registry:", newRegistryAddress);
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify new implementation on BaseScan");
        console.log("2. Use proxy address for future interactions");
    }
}

