// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { GuardedExecModuleUpgradeable } from "../src/GuardedExecModuleUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployGuardedExecModuleUpgradeable
 * @notice Deployment script for GuardedExecModule using UUPS upgradeable pattern
 * @dev Deploys the implementation and proxy, then initializes the module
 */
contract DeployGuardedExecModuleUpgradeable is Script {
    function run() external {
        // Get deployer address
        address deployer = msg.sender;
        
        // Get registry address from environment
        address registryAddress = vm.envAddress("TARGET_REGISTRY_ADDRESS");
        
        console.log("Deploying GuardedExecModuleUpgradeable...");
        console.log("Deployer:", deployer);
        console.log("Registry:", registryAddress);
        
        // Deploy implementation contract
        GuardedExecModuleUpgradeable implementation = new GuardedExecModuleUpgradeable();
        console.log("Implementation deployed at:", address(implementation));
        
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            GuardedExecModuleUpgradeable.initialize.selector,
            registryAddress,
            deployer
        );
        
        // Deploy UUPS proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));
        
        // Cast proxy to GuardedExecModuleUpgradeable
        GuardedExecModuleUpgradeable module = GuardedExecModuleUpgradeable(address(proxy));
        
        // Verify initialization
        console.log("Module name:", module.name());
        console.log("Module version:", module.version());
        console.log("Registry:", address(module.registry()));
        console.log("Owner:", module.owner());
        console.log("Initialized:", module.isInitialized(address(0)));
        
        console.log("\nDeployment successful!");
        console.log("Use this address for GUARDED_EXEC_MODULE_ADDRESS:", address(proxy));
    }
}
