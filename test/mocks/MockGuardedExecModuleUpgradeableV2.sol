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

    /**
     * @notice Registry contract for target + selector whitelist verification
     */
    TargetRegistry public registry;

    /**
     * @notice Upgrade counter (new in V2) - tracks number of upgrades for testing
     */
    uint256 public upgradeCounter;

    /**
     * @notice Upgrade message (new in V2) - stores upgrade initialization message for testing
     */
    string public upgradeMessage;

    /**
     * @notice Storage gap for future variables in upgrades
     * @dev Adjusted to 47 slots (50 - 3 new slots: upgradeCounter, upgradeMessage, and reduced gap)
     */
    uint256[47] private __gapMockV2;

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

        registry = TargetRegistry(_registry);
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
     * @param targets Array of target contract addresses
     * @param calldatas Array of encoded function calls
     * @param values Array of native ETH values to send with each call
     */
    function executeGuardedBatch(
        address[] calldata targets,
        bytes[] calldata calldatas,
        uint256[] calldata values
    )
        external
        whenNotPaused
    {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != calldatas.length) revert LengthMismatch();
        if (length != values.length) revert LengthMismatch();

        Execution[] memory executions = new Execution[](length);
        TargetRegistry reg = registry;

        // Single-pass validation and execution array building
        // All validations happen before any execution (security best practice)
        for (uint256 i = 0; i < length;) {
            bytes calldata currentCalldata = calldatas[i];
            address currentTarget = targets[i];
            uint256 currentValue = values[i];

            // Extract selector from calldata (first 4 bytes)
            if (currentCalldata.length < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
            bytes4 selector = bytes4(currentCalldata[:4]);

            // Security check 1: Verify target+selector is whitelisted
            if (!reg.isWhitelisted(currentTarget, selector)) {
                revert TargetSelectorNotWhitelisted(currentTarget, selector);
            }

            // Security check 2: Validate ERC20 transfer authorization if this is a transfer
            if (selector == TRANSFER_SELECTOR) {
                _validateERC20Transfer(currentTarget, currentCalldata, reg);
            }

            // Build execution after all validations pass
            executions[i] =
                Execution({ target: currentTarget, value: currentValue, callData: currentCalldata });

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

        address oldRegistry = address(registry);
        registry = TargetRegistry(newRegistry);

        emit RegistryUpdated(oldRegistry, newRegistry);
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
     * @param reg The cached registry instance for authorization check
     */
    function _validateERC20Transfer(
        address token,
        bytes calldata callData,
        TargetRegistry reg
    )
        internal
        view
    {
        // Standard ERC20 transfer must be exactly 68 bytes: 4 (selector) + 32 (to) + 32 (amount)
        if (callData.length != MIN_TRANSFER_LENGTH) revert InvalidCalldata();

        // Extract recipient address from calldata (bytes 4-35)
        address to = abi.decode(callData[4:36], (address));

        // Check if recipient is authorized (wallet itself, owner, or explicitly authorized)
        if (!reg.isERC20TransferAuthorized(token, to, msg.sender)) {
            revert UnauthorizedERC20Transfer(token, to);
        }
    }
}
