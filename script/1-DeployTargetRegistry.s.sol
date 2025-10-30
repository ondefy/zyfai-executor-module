// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {TargetRegistry} from "../src/registry/TargetRegistry.sol";

/**
 * @title Deploy Target Registry
 * @notice Deploy TargetRegistry contract on Base mainnet
 * @dev Run with: forge script script/1-DeployTargetRegistry.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
 */
contract DeployTargetRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying TargetRegistry ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy TargetRegistry with owner = deployer
        TargetRegistry registry = new TargetRegistry(deployer);
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Success ===");
        console.log("TargetRegistry deployed to:", address(registry));
        console.log("Owner:", deployer);
        
        // Verify registry owner
        assert(registry.owner() == deployer);
        console.log("Registry owner verified:", registry.owner());
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify TargetRegistry on BaseScan");
        console.log("2. Run script/2-UpgradeAndUpdateModule.s.sol with this registry address");
    }
}