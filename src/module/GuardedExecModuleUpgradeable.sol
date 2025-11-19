// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "../registry/TargetRegistry.sol";

/**
 * @title GuardedExecModuleUpgradeable
 * @author ZyFAI
 * @notice Executor module that allows session keys to execute whitelisted DeFi operations
 *         while maintaining smart account context. Uses UUPS upgradeable pattern.
 * @dev Session keys can execute batch operations on whitelisted target+selector combinations.
 *      All executions maintain smart account context (msg.sender = smart account).
 *      Security: Whitelist validation, ERC20 transfer restrictions, pausable, upgradeable,
 *      two-step ownership transfer for enhanced security.
 */
contract GuardedExecModuleUpgradeable is
    ERC7579ExecutorBase,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice ERC20 transfer function selector for gas optimization
     * @dev Used to identify ERC20 transfer calls for additional authorization checks
     */
    bytes4 private constant TRANSFER_SELECTOR = IERC20.transfer.selector;

    /**
     * @notice ERC20 approve function selector for gas optimization
     * @dev Used to identify ERC20 approve calls for additional authorization checks
     */
    bytes4 private constant APPROVE_SELECTOR = IERC20.approve.selector;

    /**
     * @notice Minimum calldata length required to extract function selector
     * @dev Function selector is 4 bytes, so calldata must be at least 4 bytes
     */
    uint256 private constant MIN_SELECTOR_LENGTH = 4;

    /**
     * @notice Minimum calldata length for ERC20 transfer/approve validation
     * @dev Standard ERC20 transfer/approve: 4 bytes (selector) + 32 bytes (address) + 32 bytes (amount) = 68 bytes
     */
    uint256 private constant MIN_TRANSFER_LENGTH = 68;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:zyfai.storage.GuardedExecModule
    struct GuardedExecModuleStorage {
        /**
         * @notice Registry contract for target + selector whitelist verification
         * @dev Used to verify if target+selector combinations are whitelisted.
         *      Can be updated via updateRegistry for migration.
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

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the registry address is updated
     * @param oldRegistry The previous registry address
     * @param newRegistry The new registry address
     */
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /**
     * @notice Emitted after a successful guarded batch execution
     * @param executor The caller that triggered the batch
     * @param targets Target contract addresses executed in the batch
     * @param selectors Function selectors extracted from each calldata entry
     * @param timestamp Block timestamp when the batch executed
     */
    event GuardedBatchExecuted(
        address indexed executor,
        address[] targets,
        bytes4[] selectors,
        uint256 timestamp
    );

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
     * @notice Constructor for implementation contract
     * @dev Disables initialization in implementation contract to prevent direct use.
     *      Only proxy instances should be initialized via initialize().
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
     * @dev Can only be called once by the proxy. Initializes Ownable2Step, Pausable, and UUPS
     * upgradeable.
     * @param _registry Address of the TargetRegistry contract
     * @param _owner Address that can pause/unpause and upgrade (should be multisig for production)
     */
    function initialize(address _registry, address _owner) external initializer {
        if (_registry == address(0)) revert InvalidRegistry();

        __Ownable2Step_init();
        __Ownable_init(_owner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        GuardedExecModuleStorage storage s = _getGuardedExecModuleStorage();
        s.registry = TargetRegistry(_registry);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the human-readable name of the module
     * @return Module name string
     */
    function name() external pure returns (string memory) {
        return "GuardedExecModuleUpgradeable";
    }

    /**
     * @notice Returns the semantic version of the module
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
     * @dev Always returns true as module configuration is immutable per account (registry set
     * during initialization).
     *      Parameter is unused but required by ERC7579 interface.
     * @return True (always initialized)
     */
    function isInitialized(address) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Get the registry contract address
     * @dev Returns the registry contract used for whitelist verification
     * @return The TargetRegistry contract address
     */
    function registry() external view returns (TargetRegistry) {
        return _getGuardedExecModuleStorage().registry;
    }

    /**
     * @notice Pause the module (emergency stop)
     * @dev Blocks all executeGuardedBatch calls. Use if session key is compromised or critical
     * vulnerability discovered.
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
     * @dev Registry is set during initialization, no per-account configuration needed. Required by
     * ERC7579 interface.
     * @param data Installation data (unused)
     */
    function onInstall(bytes calldata data) external override {
        // No-op: Configuration is set during initialization
    }

    /**
     * @notice Module uninstallation hook (no-op)
     * @dev No storage to clean up. Required by ERC7579 interface.
     * @param data Uninstallation data (unused)
     */
    function onUninstall(bytes calldata data) external override {
        // No-op: No storage to clean up
    }

    /**
     * @notice Execute a batch of whitelisted calls to DeFi protocols
     * @dev Permissionless function. All target+selector combinations must be whitelisted.
     *      Executions maintain smart account context (msg.sender = smart account).
     *      All validations occur before execution (checks-effects-interactions pattern).
     *      The smart account uses its own balance to forward ETH to target contracts.
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
        bytes4[] memory selectors = new bytes4[](length);
        GuardedExecModuleStorage storage s = _getGuardedExecModuleStorage();
        TargetRegistry reg = s.registry;

        // Single-pass validation and execution array building
        // All validations happen before any execution (security best practice)
        for (uint256 i = 0; i < length;) {
            bytes calldata currentCalldata = calldatas[i];
            address currentTarget = targets[i];
            uint256 currentValue = values[i];

            // Extract selector from calldata (first 4 bytes)
            if (currentCalldata.length < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
            bytes4 selector = bytes4(currentCalldata[:4]);
            selectors[i] = selector;

            // Security check 1: Verify target+selector is whitelisted
            if (!reg.isWhitelisted(currentTarget, selector)) {
                revert TargetSelectorNotWhitelisted(currentTarget, selector);
            }

            // Security check 2: Validate ERC20 transfer authorization if this is a transfer
            if (selector == TRANSFER_SELECTOR) {
                _validateERC20Transfer(currentTarget, currentCalldata, reg);
            }

            // Security check 3: Validate ERC20 approve authorization if this is an approve
            if (selector == APPROVE_SELECTOR) {
                _validateERC20Approve(currentTarget, currentCalldata, reg);
            }

            // Build execution after all validations pass
            executions[i] =
                Execution({ target: currentTarget, value: currentValue, callData: currentCalldata });

            unchecked {
                ++i;
            }
        }

        // Execute batch via smart account (maintains msg.sender = smart account)
        // The smart account uses its own balance to forward ETH to target contracts
        // based on the Execution.value fields in the executions array
        _execute(executions);

        emit GuardedBatchExecuted(msg.sender, targets, selectors, block.timestamp);
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

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Authorize an upgrade (UUPS pattern)
     * @dev Owner only. Called by UUPSUpgradeable when upgrade is attempted.
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

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

    /**
     * @notice Validate ERC20 approve authorization
     * @dev Validates calldata format and checks if approve spender is whitelisted.
     *      Spender must be a whitelisted target address in the registry (trusted DeFi contract).
     * @param token The ERC20 token address
     * @param callData The encoded approve(address spender, uint256 amount) call data
     * @param reg The cached registry instance for authorization check
     */
    function _validateERC20Approve(
        address token,
        bytes calldata callData,
        TargetRegistry reg
    )
        internal
        view
    {
        // Standard ERC20 approve must be exactly 68 bytes: 4 (selector) + 32 (spender) + 32 (amount)
        if (callData.length != MIN_TRANSFER_LENGTH) revert InvalidCalldata();

        // Extract spender address from calldata (bytes 4-35)
        address spender = abi.decode(callData[4:36], (address));

        // Check if spender is whitelisted as a target address (trusted contract)
        // Spender must be in the whitelistedTargets mapping (has at least one selector whitelisted)
        if (!reg.isWhitelistedTarget(spender)) {
            revert UnauthorizedERC20Approve(token, spender);
        }
    }
}
