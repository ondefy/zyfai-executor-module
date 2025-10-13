// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ITargetRegistry } from "./TargetRegistry.sol";
import "forge-std/console.sol";

/**
 * @title GuardedRouter
 * @notice Stateless router that executes batched calls after verifying targets against a registry.
 * @dev This contract is designed to be delegatecalled by the smart account via the GuardedExecModule.
 *      When delegatecalled, it runs in the account's context, so any external calls it makes
 *      will have msg.sender = the smart account.
 */
contract GuardedRouter {
    
    /**
     * @notice Execute a batch of calls to whitelisted targets
     * @param registryAddr The registry to check targets against
     * @param targets Array of target addresses to call
     * @param calldatas Array of calldata for each target
     * @param revertAll If true, revert entire batch if any call fails; if false, continue on failures
     * @return results Array of return data from each call
     * @return successes Array of booleans indicating success/failure of each call
     */
    function guardedBatch(
        address registryAddr,
        address[] calldata targets,
        bytes[] calldata calldatas,
        bool revertAll
    ) external returns (bytes[] memory results, bool[] memory successes) {
        console.log("=== GuardedRouter.guardedBatch START ===");
        console.log("Executing in context of (should be smart account):", address(this));
        console.log("msg.sender in router:", msg.sender);
        console.log("Number of targets:", targets.length);
        
        require(targets.length == calldatas.length, "length-mismatch");
        require(targets.length > 0, "empty-batch");
        
        ITargetRegistry registry = ITargetRegistry(registryAddr);
        
        results = new bytes[](targets.length);
        successes = new bool[](targets.length);
        
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("\n--- Call #%d", i);
            console.log("Target:", targets[i]);
            
            // Verify target is whitelisted
            require(registry.isWhitelisted(targets[i]), "target-not-whitelisted");
            console.log("Target is whitelisted: true");
            
            // Make the call
            console.log("Making call from (smart account):", address(this));
            (bool success, bytes memory result) = targets[i].call(calldatas[i]);
            
            console.log("Call success:", success);
            
            results[i] = result;
            successes[i] = success;
            
            if (!success && revertAll) {
                console.log("Call failed and revertAll=true, reverting entire batch");
                // Decode revert reason if available
                if (result.length > 0) {
                    assembly {
                        revert(add(result, 32), mload(result))
                    }
                }
                revert("batch-call-failed");
            }
        }
        
        console.log("\n=== GuardedRouter.guardedBatch END ===\n");
    }
}

