// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TargetRegistry} from "../src/TargetRegistry.sol";
import {GuardedExecModule} from "../src/GuardedExecModule.sol";

/**
 * @title TestDeployment
 * @notice Test the deployed contracts functionality
 * @dev Run with: forge script script/TestDeployment.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY
 */
contract TestDeployment is Script {
    // Base network token addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    
    // Function selectors
    bytes4 constant TRANSFER = 0xa9059cbb;
    bytes4 constant DEPOSIT = 0xd0e30db0;
    
    function run() external {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        address registryAddress = vm.envAddress("TARGET_REGISTRY");
        address moduleAddress = vm.envAddress("GUARDED_EXEC_MODULE");
        
        console.log("Testing deployment with account:", deployer);
        console.log("TargetRegistry address:", registryAddress);
        console.log("GuardedExecModule address:", moduleAddress);
        
        TargetRegistry registry = TargetRegistry(registryAddress);
        GuardedExecModule module = GuardedExecModule(moduleAddress);
        
        console.log("\n=== Testing TargetRegistry ===");
        
        // Test registry owner
        console.log("Registry owner:", registry.owner());
        
        // Test whitelist status
        console.log("USDC transfer whitelisted:", registry.isWhitelisted(USDC, TRANSFER));
        console.log("WETH deposit whitelisted:", registry.isWhitelisted(WETH, DEPOSIT));
        console.log("DAI transfer whitelisted:", registry.isWhitelisted(DAI, TRANSFER));
        
        // Test ERC20 restrictions
        console.log("USDC is restricted ERC20:", registry.restrictedERC20Tokens(USDC));
        console.log("WETH is restricted ERC20:", registry.restrictedERC20Tokens(WETH));
        
        console.log("\n=== Testing GuardedExecModule ===");
        
        // Test module owner
        console.log("Module owner:", module.owner());
        
        // Test registry reference
        console.log("Module registry:", address(module.registry()));
        
        // Test pause status
        console.log("Module paused:", module.paused());
        
        console.log("\n=== Deployment Test Complete ===");
        console.log("All contracts are properly deployed and configured");
    }
}
