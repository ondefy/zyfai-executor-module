// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TargetRegistry} from "../src/TargetRegistry.sol";

/**
 * @title SetupWhitelist
 * @notice Setup whitelist for Base network tokens
 * @dev Run after Deploy.s.sol with: forge script script/SetupWhitelist.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract SetupWhitelist is Script {
    // Base network token addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    
    // Function selectors
    bytes4 constant TRANSFER = 0xa9059cbb;
    bytes4 constant TRANSFER_FROM = 0x23b872dd;
    bytes4 constant APPROVE = 0x095ea7b3;
    bytes4 constant DEPOSIT = 0xd0e30db0;
    bytes4 constant WITHDRAW = 0x2e1a7d4d;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address registryAddress = vm.envAddress("TARGET_REGISTRY");
        
        console.log("Setting up whitelist with account:", deployer);
        console.log("TargetRegistry address:", registryAddress);
        
        TargetRegistry registry = TargetRegistry(registryAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Schedule whitelist additions (will be available after timelock)
        console.log("\n=== Scheduling Whitelist Additions ===");
        
        // USDC operations
        console.log("Scheduling USDC transfer...");
        registry.scheduleAdd(USDC, TRANSFER);
        
        console.log("Scheduling USDC transferFrom...");
        registry.scheduleAdd(USDC, TRANSFER_FROM);
        
        console.log("Scheduling USDC approve...");
        registry.scheduleAdd(USDC, APPROVE);
        
        // WETH operations
        console.log("Scheduling WETH deposit...");
        registry.scheduleAdd(WETH, DEPOSIT);
        
        console.log("Scheduling WETH withdraw...");
        registry.scheduleAdd(WETH, WITHDRAW);
        
        console.log("Scheduling WETH transfer...");
        registry.scheduleAdd(WETH, TRANSFER);
        
        // DAI operations
        console.log("Scheduling DAI transfer...");
        registry.scheduleAdd(DAI, TRANSFER);
        
        console.log("Scheduling DAI transferFrom...");
        registry.scheduleAdd(DAI, TRANSFER_FROM);
        
        console.log("Scheduling DAI approve...");
        registry.scheduleAdd(DAI, APPROVE);
        
        vm.stopBroadcast();
        
        console.log("\n=== Whitelist Setup Complete ===");
        console.log("All operations scheduled for timelock approval");
        console.log("Use ExecuteWhitelist.s.sol after timelock period to activate");
    }
}
