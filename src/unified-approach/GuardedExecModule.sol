// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "./TargetRegistry.sol";


contract GuardedExecModule is ERC7579ExecutorBase {
    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Immutable registry for target + selector whitelist verification
    /// @dev Set once in constructor, cannot be changed to prevent malicious overwrites
    TargetRegistry public immutable registry;

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidRegistry();
    error EmptyBatch();
    error LengthMismatch();
    error TargetSelectorNotWhitelisted(address target, bytes4 selector);
    error InvalidCalldata();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize the module with immutable registry
     * @dev Registry address is set once and cannot be changed
     * @param _registry Address of the target registry contract
     */
    constructor(address _registry) {
        if (_registry == address(0)) revert InvalidRegistry();
        registry = TargetRegistry(_registry);
    }

    /*//////////////////////////////////////////////////////////////
                          MODULE METADATA
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Returns the human-readable name of the module
     * @return Module name
     */
    function name() external pure returns (string memory) {
        return "GuardedExecModule";
    }
    
    /**
     * @notice Returns the version of the module
     * @return Semantic version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Checks if this contract implements the specified module type
     * @param typeId The module type ID to check (2 = EXECUTOR)
     * @return True if this is an executor module
     */
    function isModuleType(uint256 typeId) external pure override returns (bool) {
        return typeId == 2; // MODULE_TYPE_EXECUTOR
    }

    /**
     * @notice Checks if the module is initialized for a smart account
     * @dev Always returns true as configuration is immutable
     * @return True (always initialized)
     */
    function isInitialized(address) external pure override returns (bool) {
        // Always initialized as configuration is immutable
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        LIFECYCLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Module installation hook (no-op)
     * @dev Registry is immutable, no per-account configuration needed
     */
    function onInstall(bytes calldata) external override {
        // No-op: Configuration is immutable and set at deployment
    }

    /**
     * @notice Module uninstallation hook (no-op)
     * @dev No storage to clean up
     */
    function onUninstall(bytes calldata) external override {
        // No-op: No storage to clean up
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Execute a batch of whitelisted calls to DeFi protocols
     * @dev All target+selector combinations must be whitelisted in the registry
     *      Execution maintains smart account context (msg.sender = smart account)
     * 
     * @param targets Array of target contract addresses
     * @param calldatas Array of encoded function calls
     * @custom:security-note This function can be called by anyone (e.g., session keys)
     *                        but only whitelisted target+selector combinations can be called
     */
    function executeGuardedBatch(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external {
        // Input validation
        if (targets.length == 0) revert EmptyBatch();
        if (targets.length != calldatas.length) revert LengthMismatch();
        
        // Pre-flight whitelist verification for all target+selector combinations
        // This prevents wasted gas if any combination is not whitelisted
        for (uint256 i = 0; i < targets.length; i++) {
            // Extract selector from calldata (first 4 bytes)
            if (calldatas[i].length < 4) revert InvalidCalldata();
            bytes4 selector = bytes4(calldatas[i][:4]);
            
            // Check if target+selector is whitelisted
            if (!registry.isWhitelisted(targets[i], selector)) {
                revert TargetSelectorNotWhitelisted(targets[i], selector);
            }
        }

        // Build execution array for batched calls
        Execution[] memory executions = new Execution[](targets.length);
        
        for (uint256 i = 0; i < targets.length; i++) {
            // Defense in depth: double-check whitelist
            if (calldatas[i].length < 4) revert InvalidCalldata();
            bytes4 selector = bytes4(calldatas[i][:4]);
            
            if (!registry.isWhitelisted(targets[i], selector)) {
                revert TargetSelectorNotWhitelisted(targets[i], selector);
            }
            
            executions[i] = Execution({
                target: targets[i],
                value: 0,
                callData: calldatas[i]
            });
        }
        
        // Execute batch via smart account
        // This maintains msg.sender = smart account in all calls
        _execute(executions);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the configured registry address
     * @return Address of the target registry contract
     */
    function getRegistry() external view returns (address) {
        return address(registry);
    }
}

