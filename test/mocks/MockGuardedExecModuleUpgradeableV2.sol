// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "../../src/registry/TargetRegistry.sol";

/**
 * @title MockGuardedExecModuleUpgradeableV2
 * @author ZyFAI
 * @notice Mock contract for testing upgradeability - NOT for production use
 * @dev This is a test-only mock contract used in Foundry tests to verify upgrade functionality.
 *      Adds new storage variables (upgradeCounter, upgradeMessage) to test storage layout
 * compatibility.
 */
contract MockGuardedExecModuleUpgradeableV2 is 
    ERC7579ExecutorBase,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice ERC20 transfer function selector for gas optimization
     */
    bytes4 private constant TRANSFER_SELECTOR = IERC20.transfer.selector;
    
    /**
     * @notice ERC20 approve function selector for gas optimization
     */
    bytes4 private constant APPROVE_SELECTOR = IERC20.approve.selector;

    /**
     * @notice Minimum calldata length required to extract function selector
     */
    uint256 private constant MIN_SELECTOR_LENGTH = 4;

    /**
     * @notice Minimum calldata length for ERC20 transfer validation
     * @dev Standard ERC20 transfer: 4 bytes (selector) + 32 bytes (to) + 32 bytes (amount) = 68
     * bytes
     */
    uint256 private constant MIN_TRANSFER_LENGTH = 68;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @custom:storage-location erc7201:zyfai.storage.GuardedExecModule
    struct GuardedExecModuleStorage {
        /**
         * @notice Registry contract for target + selector whitelist verification
         */
        TargetRegistry registry;
    }

    // keccak256(abi.encode(uint256(keccak256("zyfai.storage.GuardedExecModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GUARDED_EXEC_MODULE_STORAGE_LOCATION =
        0x295e5725ff7abc8ecde20ecacfd357d4e36e80a3400e382495405ddf25fc1100;

    function _getGuardedExecModuleStorage() private pure returns (GuardedExecModuleStorage storage s) {
        bytes32 position = GUARDED_EXEC_MODULE_STORAGE_LOCATION;
        assembly {
            s.slot := position
        }
    }

    /**
     * @notice Upgrade counter (new in V2) - tracks number of upgrades for testing
     */
    uint256 public upgradeCounter;

    /**
     * @notice Upgrade message (new in V2) - stores upgrade initialization message for testing
     */
    string public upgradeMessage;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the registry address is updated
     * @param oldRegistry The previous registry address
     * @param newRegistry The new registry address
     */
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when registry address is zero
    error InvalidRegistry();

    /// @notice Thrown when batch operation arrays are empty
    error EmptyBatch();

    /// @notice Thrown when array lengths don't match
    error LengthMismatch();

    /// @notice Thrown when target+selector combination is not whitelisted
    /// @param target The target contract address
    /// @param selector The function selector
    error TargetSelectorNotWhitelisted(address target, bytes4 selector);

    /// @notice Thrown when ERC20 transfer is attempted to unauthorized recipient
    /// @param token The ERC20 token address
    /// @param to The unauthorized recipient address
    error UnauthorizedERC20Transfer(address token, address to);

    /// @notice Thrown when ERC20 approve is attempted to unauthorized spender
    /// @param token The ERC20 token address
    /// @param spender The unauthorized spender address
    error UnauthorizedERC20Approve(address token, address spender);

    /// @notice Thrown when calldata is invalid (too short or malformed)
    error InvalidCalldata();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor for mock implementation contract
     * @dev Disables initialization in implementation contract to prevent direct use.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the module with registry and owner
     * @dev Can only be called once by the proxy. Initializes Ownable, Pausable, and UUPS
     * upgradeable.
     * @param _registry Address of the TargetRegistry contract
     * @param _owner Address that can pause/unpause and upgrade
     */
    function initialize(address _registry, address _owner) external initializer {
        if (_registry == address(0)) revert InvalidRegistry();
        
        __Ownable_init(_owner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        GuardedExecModuleStorage storage s = _getGuardedExecModuleStorage();
        s.registry = TargetRegistry(_registry);
    }

    /**
     * @notice V2 specific initialization (called after upgrade)
     * @dev Used in tests to initialize new storage variables after upgrade. Called via
     * upgradeToAndCall.
     * @param _upgradeMessage Message to store for testing upgrade functionality
     */
    function initializeV2(string memory _upgradeMessage) external reinitializer(2) {
        upgradeMessage = _upgradeMessage;
        upgradeCounter = 1;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the human-readable name of the mock module
     * @return Module name string
     */
    function name() external pure returns (string memory) {
        return "MockGuardedExecModuleUpgradeableV2";
    }
    
    /**
     * @notice Returns the semantic version of the mock module
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    /**
     * @notice Checks if this contract implements the specified module type
     * @dev Returns true for typeId == 2 (MODULE_TYPE_EXECUTOR)
     * @param typeId The module type ID to check
     * @return True if this is an executor module
     */
    function isModuleType(uint256 typeId) external pure override returns (bool) {
        return typeId == 2;
    }

    /**
     * @notice Checks if the module is initialized for a smart account
     * @dev Always returns true as module configuration is immutable per account.
     * @return True (always initialized)
     */
    function isInitialized(address) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Pause the module (emergency stop)
     * @dev Blocks all executeGuardedBatch calls.
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the module
     * @dev Resumes normal operation, allowing executeGuardedBatch calls again.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Module installation hook (no-op)
     * @dev Registry is set during initialization, no per-account configuration needed.
     */
    function onInstall(bytes calldata) external override { }

    /**
     * @notice Module uninstallation hook (no-op)
     * @dev No storage to clean up.
     */
    function onUninstall(bytes calldata) external override { }

    /**
     * @notice Execute a batch of whitelisted calls to DeFi protocols
     * @dev Permissionless function. All target+selector combinations must be whitelisted.
     *      Executions maintain smart account context (msg.sender = smart account).
     *      All validations occur before execution (checks-effects-interactions pattern).
     * @param executions Array of Execution structs containing target, value, and callData
     */
    function executeGuardedBatch(
        Execution[] calldata executions
    )
        external
        whenNotPaused
    {
        uint256 length = executions.length;
        if (length == 0) revert EmptyBatch();
        
        address[] memory targets = new address[](length);
        bytes4[] memory selectors = new bytes4[](length);
        GuardedExecModuleStorage storage s = _getGuardedExecModuleStorage();
        TargetRegistry reg = s.registry;
        
        // Single-pass validation and execution array building
        // All validations happen before any execution (security best practice)
        for (uint256 i = 0; i < length;) {
            Execution calldata execution = executions[i];
            address target = execution.target;
            bytes calldata callData = execution.callData;
            uint256 callDataLength = callData.length;
            
            // Extract selector from calldata (first 4 bytes)
            if (callDataLength < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
            bytes4 selector = bytes4(callData[:4]);
            selectors[i] = selector;
            targets[i] = target;
            
            // Security check 1: Verify target+selector is whitelisted
            // Using auto-generated getter from public mapping to avoid duplicate bytecode
            if (!reg.whitelist(target, selector)) {
                revert TargetSelectorNotWhitelisted(target, selector);
            }
            
            // Security check 2 & 3: Validate ERC20 transfer/approve authorization
            // Most common case (non-transfer, non-approve) skips these checks entirely
            // Using else-if to avoid checking both conditions when first matches
            if (selector == TRANSFER_SELECTOR) {
                _validateERC20Transfer(target, callData, callDataLength, reg);
            } else if (selector == APPROVE_SELECTOR) {
                _validateERC20Approve(target, callData, callDataLength, reg);
            }
            
            unchecked {
                ++i;
            }
        }
        
        // Execute batch via smart account (maintains msg.sender = smart account)
        _execute(executions);
    }

    /**
     * @notice Update the registry address (for migration)
     * @dev Owner only. Allows updating registry if needed for migration or upgrades.
     * @param newRegistry The new TargetRegistry contract address
     */
    function updateRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) revert InvalidRegistry();

        GuardedExecModuleStorage storage s = _getGuardedExecModuleStorage();
        address oldRegistry = address(s.registry);
        s.registry = TargetRegistry(newRegistry);

        emit RegistryUpdated(oldRegistry, newRegistry);
    }

    /**
     * @notice Get the registry contract address
     * @dev Returns the registry contract used for whitelist verification
     * @return The TargetRegistry contract address
     */
    function registry() external view returns (TargetRegistry) {
        return _getGuardedExecModuleStorage().registry;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Authorize an upgrade (UUPS pattern)
     * @dev Owner only. Called by UUPSUpgradeable when upgrade is attempted.
     *      Increments upgradeCounter for testing purposes. Parameter is unused but required by
     * interface.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {
        upgradeCounter++; // Track upgrades for testing
    }

    /**
     * @notice Validate ERC20 transfer authorization
     * @dev Validates calldata format and checks if transfer recipient is authorized.
     *      Recipient must be: smart wallet itself, wallet owner, or explicitly authorized.
     * @param token The ERC20 token address
     * @param callData The encoded transfer(address to, uint256 amount) call data
     * @param callDataLength The length of callData (cached to avoid repeated calldata loads)
     * @param reg The cached registry instance for authorization check
     */
    function _validateERC20Transfer(
        address token,
        bytes calldata callData,
        uint256 callDataLength,
        TargetRegistry reg
    )
        internal
        view
    {
        // Standard ERC20 transfer must be exactly 68 bytes: 4 (selector) + 32 (to) + 32 (amount)
        if (callDataLength != MIN_TRANSFER_LENGTH) revert InvalidCalldata();
        
        // Extract recipient address from calldata (bytes 16-35, ignoring 12-byte padding)
        address to = address(bytes20(callData[16:36]));

        // Check if recipient is authorized (wallet itself, owner, or explicitly authorized)
        if (!reg.isERC20TransferAuthorized(token, to, msg.sender)) {
            revert UnauthorizedERC20Transfer(token, to);
        }
    }

    /**
     * @notice Validate ERC20 approve authorization
     * @dev Validates calldata format and checks if approve spender is whitelisted.
     *      Spender must be a whitelisted target address in the registry (trusted DeFi contract).
     * @param token The ERC20 token address
     * @param callData The encoded approve(address spender, uint256 amount) call data
     * @param callDataLength The length of callData (cached to avoid repeated calldata loads)
     * @param reg The cached registry instance for authorization check
     */
    function _validateERC20Approve(
        address token,
        bytes calldata callData,
        uint256 callDataLength,
        TargetRegistry reg
    )
        internal
        view
    {
        // Standard ERC20 approve must be exactly 68 bytes: 4 (selector) + 32 (spender) + 32 (amount)
        if (callDataLength != MIN_TRANSFER_LENGTH) revert InvalidCalldata();

        // Extract spender address from calldata (bytes 16-35, ignoring 12-byte padding)
        address spender = address(bytes20(callData[16:36]));

        // Check if spender is whitelisted as a target address (trusted contract)
        // Spender must be in the whitelistedTargets mapping (has at least one selector whitelisted)
        // Using auto-generated getter from public mapping to avoid duplicate bytecode
        if (!reg.whitelistedTargets(spender)) {
            revert UnauthorizedERC20Approve(token, spender);
        }
    }
}
