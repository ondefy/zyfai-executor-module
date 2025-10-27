// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TargetRegistry} from "../src/TargetRegistry.sol";

/**
 * @title ExecuteWhitelist
 * @notice Execute scheduled whitelist operations after timelock period
 * @dev Run after timelock period with: forge script script/ExecuteWhitelist.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract ExecuteWhitelist is Script {
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
        
        console.log("Executing whitelist operations with account:", deployer);
        console.log("TargetRegistry address:", registryAddress);
        
        TargetRegistry registry = TargetRegistry(registryAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Execute scheduled operations
        console.log("\n=== Executing Whitelist Operations ===");
        
        // Execute each operation directly
        try registry.executeOperation(USDC, TRANSFER) {
            console.log("Executed USDC transfer");
        } catch {
            console.log("Failed to execute USDC transfer");
        }
        
        try registry.executeOperation(USDC, TRANSFER_FROM) {
            console.log("Executed USDC transferFrom");
        } catch {
            console.log("Failed to execute USDC transferFrom");
        }
        
        try registry.executeOperation(USDC, APPROVE) {
            console.log("Executed USDC approve");
        } catch {
            console.log("Failed to execute USDC approve");
        }
        
        try registry.executeOperation(WETH, DEPOSIT) {
            console.log("Executed WETH deposit");
        } catch {
            console.log("Failed to execute WETH deposit");
        }
        
        try registry.executeOperation(WETH, WITHDRAW) {
            console.log("Executed WETH withdraw");
        } catch {
            console.log("Failed to execute WETH withdraw");
        }
        
        try registry.executeOperation(WETH, TRANSFER) {
            console.log("Executed WETH transfer");
        } catch {
            console.log("Failed to execute WETH transfer");
        }
        
        try registry.executeOperation(DAI, TRANSFER) {
            console.log("Executed DAI transfer");
        } catch {
            console.log("Failed to execute DAI transfer");
        }
        
        try registry.executeOperation(DAI, TRANSFER_FROM) {
            console.log("Executed DAI transferFrom");
        } catch {
            console.log("Failed to execute DAI transferFrom");
        }
        
        try registry.executeOperation(DAI, APPROVE) {
            console.log("Executed DAI approve");
        } catch {
            console.log("Failed to execute DAI approve");
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== Whitelist Execution Complete ===");
        console.log("All operations have been processed");
    }
}
