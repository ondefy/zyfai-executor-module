// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {TargetRegistry} from "../src/registry/TargetRegistry.sol";
import {GuardedExecModuleUpgradeable} from "../src/module/GuardedExecModuleUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Deploy All and Upgrade
 * @notice Complete deployment: TargetRegistry + GuardedExecModule upgrade + registry update
 * @dev Run with: forge script script/DeployTargetRegistryAndUpgrade.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
 * 
 * PREREQUISITES:
 * - Set PROXY_ADDRESS env variable (existing proxy from previous deployment)
 */
contract DeployTargetRegistryAndUpgrade is Script {
    // Existing proxy address (from previous deployment)
    address constant PROXY_ADDRESS = 0x7B3072f06105c08de4997bdC74C7095327fD475c;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Complete Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Existing proxy:", PROXY_ADDRESS);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy new TargetRegistry
        console.log("\n=== Step 1: Deploy TargetRegistry ===");
        TargetRegistry registry = new TargetRegistry(deployer);
        console.log("TargetRegistry deployed to:", address(registry));
        console.log("Registry owner:", deployer);
        
        // Step 2: Deploy new implementation
        console.log("\n=== Step 2: Deploy new GuardedExecModuleUpgradeable implementation ===");
        GuardedExecModuleUpgradeable newImplementation = new GuardedExecModuleUpgradeable();
        console.log("New implementation deployed to:", address(newImplementation));
        
        // Step 3: Upgrade proxy to new implementation
        console.log("\n=== Step 3: Upgrade proxy to new implementation ===");
        GuardedExecModuleUpgradeable proxy = GuardedExecModuleUpgradeable(PROXY_ADDRESS);
        
        // Verify current owner
        require(proxy.owner() == deployer, "Deployer is not the owner");
        console.log("Owner verified:", proxy.owner());
        
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("Proxy upgraded to:", address(newImplementation));
        
        // Step 4: Update registry on proxy
        console.log("\n=== Step 4: Update registry on proxy ===");
        proxy.updateRegistry(address(registry));
        console.log("Registry updated to:", address(registry));
        
        vm.stopBroadcast();
        
        // Verify everything
        console.log("\n=== Verification ===");
        assert(address(proxy.registry()) == address(registry));
        assert(registry.owner() == deployer);
        console.log("Registry verified:", address(proxy.registry()));
        console.log("Proxy owner:", proxy.owner());
        
        console.log("\n=== Deployment Summary ===");
        console.log("PROXY_ADDRESS:", PROXY_ADDRESS);
        console.log("NEW_IMPLEMENTATION:", address(newImplementation));
        console.log("NEW_REGISTRY:", address(registry));
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify new TargetRegistry on BaseScan");
        console.log("2. Verify new implementation on BaseScan");
        console.log("3. Share these addresses with your team");
    }
}

