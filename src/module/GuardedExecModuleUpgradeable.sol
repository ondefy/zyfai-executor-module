// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "../registry/TargetRegistry.sol";

/**
 * @title GuardedExecModuleUpgradeable
 * @author Zyfi
 * @notice GuardedExecModule executor module using OpenZeppelin UUPS upgradeable pattern
 * @dev This module allows session keys to execute whitelisted DeFi operations
 *      while maintaining smart account context (msg.sender = smart account).
 *      Pausable functionality provides emergency stop for compromised session keys.
 *      Upgradeable via UUPS pattern to allow fixing bugs and adding features.
 */
contract GuardedExecModuleUpgradeable is 
    ERC7579ExecutorBase,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice ERC20 transfer selector constant for gas optimization
    bytes4 private constant TRANSFER_SELECTOR = IERC20.transfer.selector;
    
    /// @notice Minimum calldata length for selector extraction
    uint256 private constant MIN_SELECTOR_LENGTH = 4;
    
    /// @notice Minimum calldata length for ERC20 transfer validation
    /// @dev 4 bytes (selector) + 32 bytes (to) + 32 bytes (amount) = 68 bytes
    uint256 private constant MIN_TRANSFER_LENGTH = 68;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Registry for target + selector whitelist verification
    /// @dev Can be changed via upgrade in case of registry migration
    TargetRegistry public registry;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidRegistry();
    error EmptyBatch();
    error LengthMismatch();
    error TargetSelectorNotWhitelisted(address target, bytes4 selector);
    error UnauthorizedERC20Transfer(address token, address to);
    error InvalidCalldata();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable initialization in implementation contract
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize the module with registry and owner
     * @dev Can only be called once by the proxy
     * @param _registry Address of the TargetRegistry contract
     * @param _owner Address that can pause/unpause and upgrade (should be multisig)
     */
    function initialize(address _registry, address _owner) external initializer {
        if (_registry == address(0)) revert InvalidRegistry();
        
        __Ownable_init(_owner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        registry = TargetRegistry(_registry);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Returns the human-readable name of the module
     * @return Module name
     */
    function name() external pure returns (string memory) {
        return "GuardedExecModuleUpgradeable";
    }
    
    /**
     * @notice Returns the version of the module
     * @return Semantic version string
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
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
     * @dev Always returns true as configuration is immutable per account
     * @return True (always initialized)
     */
    function isInitialized(address) external pure override returns (bool) {
        // Always initialized as configuration is immutable
        return true;
    }
    
    /**
     * @notice Pause the module (emergency stop)
     * @dev Stops all executeGuardedBatch calls - use if session key compromised
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the module
     * @dev Allows executeGuardedBatch calls again
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Module installation hook (no-op)
     * @dev Registry is set during initialization, no per-account configuration needed
     */
    function onInstall(bytes calldata) external override {
        // No-op: Configuration is set during initialization
    }

    /**
     * @notice Module uninstallation hook (no-op)
     * @dev No storage to clean up
     */
    function onUninstall(bytes calldata) external override {
        // No-op: No storage to clean up
    }
    
    /**
     * @notice Execute a batch of whitelisted calls to DeFi protocols
     * @dev All target+selector combinations must be whitelisted in the registry
     *      Execution maintains smart account context (msg.sender = smart account)
     *      Can be paused in emergency (e.g., compromised session key)
     * 
     * @param targets Array of target contract addresses
     * @param calldatas Array of encoded function calls
     * @param values Array of native asset values (ETH) to send with each call
     * @custom:security-note This function can be called by anyone (e.g., session keys)
     *                        but only whitelisted target+selector combinations can be called
     *                        Can be emergency stopped by pause controller
     * @custom:optimization Gas-optimized with unchecked increments and cached lengths
     */
    function executeGuardedBatch(
        address[] calldata targets,
        bytes[] calldata calldatas,
        uint256[] calldata values
    ) external whenNotPaused {
        // Input validation
        uint256 length = targets.length; // Cache length for gas savings
        if (length == 0) revert EmptyBatch();
        if (length != calldatas.length) revert LengthMismatch();
        if (length != values.length) revert LengthMismatch();
        
        // Build execution array (allocate once)
        Execution[] memory executions = new Execution[](length);
        
        // Single-pass validation and execution array building
        // SECURITY: All validations happen before any execution
        for (uint256 i = 0; i < length;) {
            bytes calldata currentCalldata = calldatas[i];
            address currentTarget = targets[i];
            uint256 currentValue = values[i];
            
            // Extract selector from calldata (first 4 bytes)
            if (currentCalldata.length < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
            bytes4 selector = bytes4(currentCalldata[:4]);
            
            // SECURITY CHECK 1: Whitelist verification
            if (!registry.isWhitelisted(currentTarget, selector)) {
                revert TargetSelectorNotWhitelisted(currentTarget, selector);
            }
            
            // SECURITY CHECK 2: ERC20 transfer restriction check
            if (selector == TRANSFER_SELECTOR) {
                _validateERC20Transfer(currentTarget, currentCalldata);
            }
            
            // Build execution after all validations pass
            // NOTE: value field supports native ETH transfers (e.g., for ETH vaults)
            executions[i] = Execution({
                target: currentTarget,
                value: currentValue,
                callData: currentCalldata
            });
            
            unchecked { ++i; } // Safe: i < length, cannot overflow
        }
        
        // Execute batch via smart account
        // This maintains msg.sender = smart account in all calls
        _execute(executions);
    }

    /**
     * @notice Update the registry address (for migration)
     * @dev Only owner can update the registry
     * @param newRegistry The new registry address
     */
    function updateRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) revert InvalidRegistry();
        
        address oldRegistry = address(registry);
        registry = TargetRegistry(newRegistry);
        
        emit RegistryUpdated(oldRegistry, newRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Authorize an upgrade
     * @dev Only owner can authorize upgrades
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @notice Validate ERC20 transfer for restricted tokens
     * @dev Checks if transfer recipient is authorized (smart wallet or owner)
     * @param token The ERC20 token address
     * @param callData The encoded transfer call data
     */
    function _validateERC20Transfer(address token, bytes calldata callData) internal view {
        // Decode transfer(address to, uint256 amount) parameters
        if (callData.length < MIN_TRANSFER_LENGTH) revert InvalidCalldata();
        
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
