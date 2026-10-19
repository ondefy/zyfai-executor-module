// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "../registry/TargetRegistry.sol";
import { IAaveV4Spoke } from "../interfaces/IAaveV4Spoke.sol";

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
     * @notice Selector of `setAuthorization(address,bool)` (Morpho Blue-style operator grant)
     * @dev A call to this selector makes the smart account grant `authorized` protocol-wide
     *      withdraw/borrow rights over its positions (e.g. Morpho Blue `setAuthorization`).
     *      The grantee argument must be ADAPTER, so a session key can never authorize any
     *      other address.
     */
    bytes4 private constant SET_AUTHORIZATION_SELECTOR = 0xeecea000;

    /**
     * @notice Selector of `setOperator(address,bool)` (ERC-7540 operator grant, e.g. SuperVault)
     * @dev Same calldata layout and grantee rule as SET_AUTHORIZATION_SELECTOR: an operator can
     *      act on the smart account's vault requests, so it must be ADAPTER.
     */
    bytes4 private constant SET_OPERATOR_SELECTOR = 0x558a7297;

    /**
     * @notice Selector of Aave v4 Spoke `borrow(uint256,uint256,address)`
     * @dev Of the Spoke position calls (supply, withdraw, borrow, repay, setUsingAsCollateral),
     *      this one, SPOKE_WITHDRAW_SELECTOR and SPOKE_SET_COLLATERAL_SELECTOR are the only ones
     *      that can lower the caller's health factor (`supply` and `repay` only raise it).
     *      The Spoke itself only enforces health factor >= 1, so without
     *      a margin a session key could borrow to the edge and liquidate the smart account from
     *      its own EOA (permissionless `liquidationCall`, liquidator takes collateral + bonus).
     */
    bytes4 private constant SPOKE_BORROW_SELECTOR = 0xd6bda0c0;

    /// @notice Selector of Aave v4 Spoke `withdraw(uint256,uint256,address)`
    bytes4 private constant SPOKE_WITHDRAW_SELECTOR = 0x0ad58d2f;

    /// @notice Selector of Aave v4 Spoke `setUsingAsCollateral(uint256,bool,address)`
    bytes4 private constant SPOKE_SET_COLLATERAL_SELECTOR = 0x9e35c533;

    /**
     * @notice Minimum Aave v4 Spoke health factor (WAD) a batch may leave the smart account at
     * @dev 1.5 instead of the Spoke's 1.0 liquidation threshold, so a session key cannot park the
     *      position next to liquidation; collateral must drop by a third before liquidation,
     *      which leaves room for gap moves on volatile collateral such as tokenized equities.
     */
    uint256 private constant MIN_HEALTH_FACTOR = 1.5e18;

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
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The only address a session key may grant via setAuthorization / setOperator
     * @dev Lives in the implementation bytecode, not proxy storage: changing it requires
     *      deploying a new implementation and upgrading the proxy.
     */
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable ADAPTER;

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

    /// @notice Thrown when the Adapter address passed to the constructor is zero
    error InvalidAdapter();

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

    /// @notice Thrown when setAuthorization or setOperator grants an unauthorized address
    /// @param target The protocol contract address (e.g. Morpho Blue singleton, SuperVault)
    /// @param authorized The unauthorized grantee address
    error UnauthorizedAuthorizationGrant(address target, address authorized);

    /// @notice Thrown when a batch leaves the smart account below MIN_HEALTH_FACTOR on a Spoke
    /// @param spoke The Aave v4 Spoke whose health factor check failed
    /// @param healthFactor The smart account's health factor on that Spoke after the batch (WAD)
    error HealthFactorTooLow(address spoke, uint256 healthFactor);

    /// @notice Thrown when calldata is invalid (too short or malformed)
    error InvalidCalldata();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Constructor for implementation contract
     * @dev Disables initialization in implementation contract to prevent direct use.
     *      Only proxy instances should be initialized via initialize().
     * @param _adapter The Zyfai Adapter proxy for this deployment (the only allowed grantee)
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _adapter) {
        if (_adapter == address(0)) revert InvalidAdapter();
        ADAPTER = _adapter;
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
        return "2.1.0";
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
     *      After execution, every target called with an Aave v4 Spoke borrow, withdraw or
     *      setUsingAsCollateral selector must report a health factor >= MIN_HEALTH_FACTOR for the
     *      smart account, otherwise the whole batch reverts. The check runs once per Spoke at the
     *      end of the batch, so intermediate states (e.g. borrow then repay) are allowed.
     *      Any target whitelisted with one of those selectors must be an Aave v4 Spoke: on any
     *      other contract the `getUserAccountData` call reverts the batch. Never whitelist these
     *      Spoke selectors: `setUserPositionManager`, `setUserPositionManagersWithSig` and
     *      `multicall` route around this check, `updateUserDynamicConfig` can lower the health
     *      factor unchecked, and `liquidationCall` spends the smart account's funds on others.
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
        address[] memory spokes = new address[](length);
        uint256 spokeCount;
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
            } else if (
                selector == SET_AUTHORIZATION_SELECTOR || selector == SET_OPERATOR_SELECTOR
            ) {
                _validateAuthorizationGrant(target, callData, callDataLength);
            } else if (
                selector == SPOKE_BORROW_SELECTOR || selector == SPOKE_WITHDRAW_SELECTOR
                    || selector == SPOKE_SET_COLLATERAL_SELECTOR
            ) {
                spokeCount = _recordSpoke(spokes, spokeCount, target);
            }
            
            unchecked {
                ++i;
            }
        }
        
        // Execute batch via smart account (maintains msg.sender = smart account)
        // The smart account uses its own balance to forward ETH to target contracts
        // based on the Execution.value fields in the executions array
        _execute(executions);

        _validateSpokeHealthFactors(spokes, spokeCount);

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

    /**
     * @notice Validate a protocol authorization grant (`setAuthorization(address,bool)` or
     *         `setOperator(address,bool)`)
     * @dev A grant like Morpho Blue `setAuthorization` gives the grantee global withdraw and
     *      borrow rights over the smart account's positions, bypassing every receiver binding
     *      downstream. The grantee must therefore be ADAPTER, which pins the receiver to the
     *      smart account. Revokes (bool = false) are not restricted.
     * @param target The protocol contract address (e.g. Morpho Blue singleton, SuperVault)
     * @param callData The encoded (address grantee, bool approved) call data
     * @param callDataLength The length of callData (cached to avoid repeated calldata loads)
     */
    function _validateAuthorizationGrant(
        address target,
        bytes calldata callData,
        uint256 callDataLength
    )
        internal
        view
    {
        // Grant calls must be exactly 68 bytes: 4 (selector) + 32 (grantee) + 32 (bool)
        if (callDataLength != MIN_TRANSFER_LENGTH) revert InvalidCalldata();

        // A revoke only removes rights, so it is allowed for any grantee (including one granted
        // under an earlier rule). Only an exact-zero bool word counts as a revoke.
        if (bytes32(callData[36:68]) == bytes32(0)) return;

        // Extract grantee address from calldata (bytes 16-35, ignoring 12-byte padding)
        address authorized = address(bytes20(callData[16:36]));

        if (authorized != ADAPTER) revert UnauthorizedAuthorizationGrant(target, authorized);
    }

    /**
     * @notice Append a Spoke to the list checked after execution, unless already present
     * @dev Linear scan; batches are small.
     * @param spokes The Spokes recorded so far (sized to the batch length)
     * @param count The number of Spokes recorded so far
     * @param spoke The Spoke targeted by the current execution
     * @return The updated number of recorded Spokes
     */
    function _recordSpoke(
        address[] memory spokes,
        uint256 count,
        address spoke
    )
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < count;) {
            if (spokes[i] == spoke) return count;
            unchecked {
                ++i;
            }
        }
        spokes[count] = spoke;
        unchecked {
            return count + 1;
        }
    }

    /**
     * @notice Require the smart account's health factor on each recorded Spoke to be at least
     *         MIN_HEALTH_FACTOR
     * @dev Runs after execution. msg.sender is the smart account, and the Spoke binds these calls
     *      to its position: `onBehalfOf` must be the caller unless the caller is a
     *      governance-activated position manager approved by `onBehalfOf`.
     * @param spokes The Spokes touched by health-factor-lowering calls in this batch
     * @param count The number of recorded Spokes
     */
    function _validateSpokeHealthFactors(address[] memory spokes, uint256 count) internal view {
        for (uint256 i = 0; i < count;) {
            uint256 healthFactor =
                IAaveV4Spoke(spokes[i]).getUserAccountData(msg.sender).healthFactor;
            if (healthFactor < MIN_HEALTH_FACTOR) {
                revert HealthFactorTooLow(spokes[i], healthFactor);
            }
            unchecked {
                ++i;
            }
        }
    }
}
