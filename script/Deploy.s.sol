// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TargetRegistry} from "../src/TargetRegistry.sol";
import {GuardedExecModule} from "../src/GuardedExecModule.sol";

/**
 * @title Deploy
 * @notice Deploy TargetRegistry and GuardedExecModule contracts
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy TargetRegistry
        console.log("\n=== Deploying TargetRegistry ===");
        TargetRegistry registry = new TargetRegistry(deployer);
        console.log("TargetRegistry deployed to:", address(registry));
        
        // Deploy GuardedExecModule
        console.log("\n=== Deploying GuardedExecModule ===");
        GuardedExecModule module = new GuardedExecModule(address(registry), deployer);
        console.log("GuardedExecModule deployed to:", address(module));
        
        vm.stopBroadcast();
        
        // Print deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", vm.envString("NETWORK"));
        console.log("Deployer:", deployer);
        console.log("TargetRegistry:", address(registry));
        console.log("GuardedExecModule:", address(module));
        
        // Test pre-whitelisted operations
        console.log("\n=== Pre-whitelisted Operations ===");
        console.log("AAVE supply whitelisted:", registry.isWhitelisted(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5, 0x617ba037));
        console.log("USDC transfer whitelisted:", registry.isWhitelisted(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 0xa9059cbb));
        console.log("USDC approve whitelisted:", registry.isWhitelisted(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 0x095ea7b3));
        console.log("USDC is restricted ERC20:", registry.restrictedERC20Tokens(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        
        // Save addresses to file
        string memory addresses = string(abi.encodePacked(
            "TARGET_REGISTRY=", vm.toString(address(registry)), "\n",
            "GUARDED_EXEC_MODULE=", vm.toString(address(module)), "\n",
            "DEPLOYER=", vm.toString(deployer), "\n"
        ));
        
        // vm.writeFile("deployments.txt", addresses);
        console.log("\nAddresses saved to deployments.txt");
    }
}
