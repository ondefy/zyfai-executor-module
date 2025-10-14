// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "./TargetRegistry.sol";

/**
 * @title GuardedExecModule
 * @author Zyfi
 * @notice Production-ready unified executor module using OpenZeppelin TimelockController
 * @dev This module allows session keys to execute whitelisted DeFi operations
 *      while maintaining smart account context (msg.sender = smart account).
 *      Pausable functionality provides emergency stop for compromised session keys.
 */
contract GuardedExecModule is ERC7579ExecutorBase, Pausable {
    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Immutable registry for target + selector whitelist verification
    /// @dev Set once in constructor, cannot be changed to prevent malicious overwrites
    TargetRegistry public immutable registry;
    
    /// @notice Address that can pause/unpause the module (emergency controller)
    address public pauseController;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PauseControllerUpdated(address indexed oldController, address indexed newController);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error OnlyPauseController();
    
    error InvalidRegistry();
    error EmptyBatch();
    error LengthMismatch();
    error TargetSelectorNotWhitelisted(address target, bytes4 selector);
    error UnauthorizedERC20Transfer(address token, address to);
    error InvalidCalldata();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize the module with immutable registry and pause controller
     * @dev Registry address is set once and cannot be changed
     * @param _registry Address of the TargetRegistry contract
     * @param _pauseController Address that can pause/unpause (should be multisig)
     */
    constructor(address _registry, address _pauseController) {
        if (_registry == address(0)) revert InvalidRegistry();
        if (_pauseController == address(0)) revert OnlyPauseController();
        registry = TargetRegistry(_registry);
        pauseController = _pauseController;
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
                          PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyPauseController() {
        if (msg.sender != pauseController) revert OnlyPauseController();
        _;
    }
    
    /**
     * @notice Pause the module (emergency stop)
     * @dev Stops all executeGuardedBatch calls - use if session key compromised
     */
    function pause() external onlyPauseController {
        _pause();
    }
    
    /**
     * @notice Unpause the module
     * @dev Allows executeGuardedBatch calls again
     */
    function unpause() external onlyPauseController {
        _unpause();
    }
    
    /**
     * @notice Update the pause controller address
     * @dev Only current pause controller can transfer control
     * @param newController New pause controller address
     */
    function updatePauseController(address newController) external onlyPauseController {
        if (newController == address(0)) revert OnlyPauseController();
        address oldController = pauseController;
        pauseController = newController;
        emit PauseControllerUpdated(oldController, newController);
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
     *      Can be paused in emergency (e.g., compromised session key)
     * 
     * @param targets Array of target contract addresses
     * @param calldatas Array of encoded function calls
     * @custom:security-note This function can be called by anyone (e.g., session keys)
     *                        but only whitelisted target+selector combinations can be called
     *                        Can be emergency stopped by pause controller
     */
    function executeGuardedBatch(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external whenNotPaused {
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
            
            // Additional ERC20 transfer restriction check
            if (selector == IERC20.transfer.selector) {
                _validateERC20Transfer(targets[i], calldatas[i]);
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
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate ERC20 transfer for restricted tokens
     * @dev Checks if transfer recipient is authorized (smart wallet or owner)
     * @param token The ERC20 token address
     * @param callData The encoded transfer call data
     */
    function _validateERC20Transfer(address token, bytes calldata callData) internal view {
        // Decode transfer(address to, uint256 amount) parameters
        if (callData.length < 68) revert InvalidCalldata(); // 4 (selector) + 32 (to) + 32 (amount)        
        
        address to = abi.decode(callData[4:36], (address));

        // Check if this transfer is authorized for restricted tokens
        if (!registry.isERC20TransferAuthorized(token, to, msg.sender)) {
            revert UnauthorizedERC20Transfer(token, to);
        }
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

