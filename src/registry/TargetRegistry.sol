// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import { ISafeWallet } from "../interfaces/ISafeWallet.sol";

/**
 * @title TargetRegistry
 * @author ZyFAI
 * @notice Registry contract that manages whitelisting of target addresses and function selectors
 *         for secure DeFi operations. Uses OpenZeppelin's TimelockController for time-delayed
 *         whitelist modifications, providing protection against malicious or accidental changes.
 * @dev This contract implements a two-phase commit pattern:
 *      1. Owner schedules whitelist changes (add/remove) which are subject to a timelock delay
 *      2. After the timelock expires, anyone can execute the scheduled operation
 *      
 *      Security Features:
 *      - Timelock delay prevents immediate malicious changes
 *      - Pausable functionality for emergency stops
 *      - Only owner can schedule operations
 *      - Batch operations supported for gas efficiency
 *      - ERC20 transfer recipient authorization for additional security
 *      
 *      The timelock delay is set to 1 day to provide adequate protection while maintaining reasonable responsiveness.
 */
contract TargetRegistry is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice OpenZeppelin TimelockController instance that enforces 1 day delay on whitelist changes
     * @dev Immutable. Controls access to _addToWhitelist and _removeFromWhitelist functions.
     */
    TimelockController public immutable timelock;
    
    /**
     * @notice Whitelist mapping: target address => function selector => is whitelisted
     * @dev Stores whether target+selector combinations are whitelisted. Only timelock-controlled functions can modify.
     *
     * Example: whitelist[uniswapRouter][swap.selector] = true means swap() on Uniswap
     *      router is allowed to be called by session keys via the executor module.
     */
    mapping(address => mapping(bytes4 => bool)) public whitelist;
    
    /**
     * @notice Operation metadata structure for tracking scheduled whitelist changes
     * @dev Stores operation ID, operation type (add/remove), and unique salt for re-scheduling.
     */
    struct OpMeta {
        bytes32 operationId;
        bool isAdd;
        bytes32 salt;
    }
    
    /**
     * @notice Mapping from (target, selector) to operation metadata
     * @dev Tracks pending whitelist operations. Prevents duplicate scheduling. Cleared after execution/cancellation.
     */
    mapping(address => mapping(bytes4 => OpMeta)) public opMeta;
    
    /**
     * @notice Mapping of authorized ERC20 token recipients: token => recipient => is allowed
     * @dev Controls which addresses can receive ERC20 tokens. Transfers allowed to: wallet itself, wallet owners, or authorized recipients.
     */
    mapping(address => mapping(address => bool)) public allowedERC20TokenRecipients;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Emitted when a whitelist operation (add/remove) is scheduled via timelock
     * @param operationId The unique operation ID from TimelockController
     * @param target The target contract address
     * @param selector The function selector
     * @param executeAfter The timestamp after which the operation can be executed
     */
    event TargetSelectorScheduled(
        bytes32 indexed operationId,
        address indexed target,
        bytes4 indexed selector,
        uint256 executeAfter
    );
    
    /**
     * @notice Emitted when a target+selector combination is added to the whitelist
     * @param target The target contract address that was whitelisted
     * @param selector The function selector that was whitelisted
     */
    event TargetSelectorAdded(
        address indexed target,
        bytes4 indexed selector
    );
    
    /**
     * @notice Emitted when a target+selector combination is removed from the whitelist
     * @param target The target contract address that was removed
     * @param selector The function selector that was removed
     */
    event TargetSelectorRemoved(
        address indexed target,
        bytes4 indexed selector
    );
    
    /**
     * @notice Emitted when an ERC20 token recipient authorization is added or removed
     * @param token The ERC20 token address
     * @param recipient The recipient address being authorized or deauthorized
     * @param authorized True if authorized, false if deauthorized
     */
    event ERC20TokenRecipientAuthorized(
        address indexed token,
        address indexed recipient,
        bool authorized
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Thrown when target address is zero address
    error InvalidTarget();
    
    /// @notice Thrown when function selector is zero (bytes4(0))
    error InvalidSelector();
    
    /// @notice Thrown when attempting to add a target+selector that is already whitelisted
    error AlreadyWhitelisted();
    
    /// @notice Thrown when attempting to remove a target+selector that is not whitelisted
    error NotWhitelisted();
    
    /// @notice Thrown when attempting to schedule an operation for a (target, selector)
    ///          that already has a pending operation
    error PendingOperationExists();
    
    /// @notice Thrown when an ERC20 transfer is attempted to an unauthorized recipient
    /// @param token The ERC20 token address
    /// @param to The unauthorized recipient address
    error UnauthorizedERC20Transfer(address token, address to);
    
    /// @notice Thrown when ERC20 token address is zero
    error InvalidERC20Token();
    
    /// @notice Thrown when recipient address is zero
    error InvalidRecipient();
    
    /// @notice Thrown when batch operation arrays are empty
    error EmptyBatch();
    
    /// @notice Thrown when array lengths don't match (e.g., targets and selectors arrays)
    error LengthMismatch();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize registry with OpenZeppelin TimelockController
     * @dev Creates TimelockController with 1 day delay. Owner schedules operations, anyone can execute after delay.
     * @param admin The address that will own this contract (should be multisig for production)
     */
    constructor(address admin) Ownable(admin) {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        
        proposers[0] = address(this);
        executors[0] = address(0); // Anyone can execute after timelock
        
        timelock = new TimelockController(1 days, proposers, executors, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Pause the registry (emergency stop)
     * @dev Blocks scheduleAdd and scheduleRemove when paused. Does not affect already-scheduled operations or view functions.
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the registry
     * @dev Resumes normal operation, allowing scheduling operations again.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Add authorized recipient(s) for a specific ERC20 token (batch operation)
     * @dev Owner only. Immediate operation (no timelock). Authorizes recipients for ERC20 transfers.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses to authorize
     */
    function addAllowedERC20TokenRecipient(address token, address[] calldata recipients) external onlyOwner {
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length;) {
            _addAllowedERC20TokenRecipient(token, recipients[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Remove authorized recipient(s) for a specific ERC20 token (batch operation)
     * @dev Owner only. Immediate operation (no timelock). Removes recipient authorization.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses to remove
     */
    function removeAllowedERC20TokenRecipient(address token, address[] calldata recipients) external onlyOwner {
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length;) {
            _removeAllowedERC20TokenRecipient(token, recipients[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Check if an ERC20 transfer to a specific recipient is authorized
     * @dev Called by GuardedExecModule. Authorized if recipient is: explicitly authorized, wallet itself, or wallet owner.
     * @param token The ERC20 token address
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @return True if the transfer is authorized
     */
    function isERC20TransferAuthorized(
        address token,
        address to,
        address smartWallet
    ) external view returns (bool) {
        return _isAuthorizedRecipient(to, smartWallet, token);
    }
    
    /**
     * @notice Schedule adding target+selector(s) to whitelist (batch operation)
     * @dev Owner only. Schedules whitelist additions through timelock (1 day delay). After delay, anyone can execute.
     * @param targets Array of contract addresses to whitelist
     * @param selectors Array of function selectors to whitelist
     * @return operationIds Array of operation IDs from TimelockController
     */
    function scheduleAdd(address[] calldata targets, bytes4[] calldata selectors) 
        external 
        onlyOwner 
        whenNotPaused
        returns (bytes32[] memory operationIds) 
    {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != selectors.length) revert LengthMismatch();
        
        operationIds = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            operationIds[i] = _scheduleAdd(targets[i], selectors[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Schedule removing target+selector(s) from whitelist (batch operation)
     * @dev Owner only. Schedules whitelist removals through timelock (1 day delay). After delay, anyone can execute.
     * @param targets Array of contract addresses to remove from whitelist
     * @param selectors Array of function selectors to remove from whitelist
     * @return operationIds Array of operation IDs from TimelockController
     */
    function scheduleRemove(address[] calldata targets, bytes4[] calldata selectors) 
        external 
        onlyOwner 
        whenNotPaused
        returns (bytes32[] memory operationIds) 
    {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != selectors.length) revert LengthMismatch();
        
        operationIds = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            operationIds[i] = _scheduleRemove(targets[i], selectors[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Execute scheduled operation(s) after timelock delay expires (batch operation)
     * @dev Permissionless function. Finalizes scheduled whitelist changes after 1 day delay. Anyone can execute.
     * @param targets Array of target addresses
     * @param selectors Array of function selectors
     */
    function executeOperation(address[] calldata targets, bytes4[] calldata selectors) external {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != selectors.length) revert LengthMismatch();
        
        for (uint256 i = 0; i < length;) {
            _executeOperation(targets[i], selectors[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Cancel pending operation(s) before they execute (batch operation)
     * @dev Owner only. Cancels scheduled operations that haven't executed yet. Immediate cancellation.
     * @param targets Array of target addresses
     * @param selectors Array of function selectors
     */
    function cancelOperation(address[] calldata targets, bytes4[] calldata selectors) external onlyOwner {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != selectors.length) revert LengthMismatch();
        
        for (uint256 i = 0; i < length;) {
            _cancelOperation(targets[i], selectors[i]);
            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Generate unique salt for operation scheduling
     * @dev Creates unique salt using target, selector, timestamp, and block randomness.
     *      Enables re-scheduling same (target, selector) by generating unique operation IDs.
     * @param target The target contract address
     * @param selector The function selector
     * @return Unique salt for the timelock operation
     */
    function _newSalt(address target, bytes4 selector) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector, block.timestamp, block.prevrandao));
    }

    /**
     * @notice Internal function to add authorized recipient for ERC20 token
     * @dev Validates inputs and authorizes recipient. Called by addAllowedERC20TokenRecipient batch function.
     * @param token The ERC20 token address
     * @param recipient The recipient address to authorize
     */
    function _addAllowedERC20TokenRecipient(address token, address recipient) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (recipient == address(0)) revert InvalidRecipient();
        if (allowedERC20TokenRecipients[token][recipient]) revert AlreadyWhitelisted();
        
        allowedERC20TokenRecipients[token][recipient] = true;
        emit ERC20TokenRecipientAuthorized(token, recipient, true);
    }
    
    /**
     * @notice Internal function to remove authorized recipient for ERC20 token
     * @dev Validates inputs and removes recipient authorization. Called by removeAllowedERC20TokenRecipient batch function.
     * @param token The ERC20 token address
     * @param recipient The recipient address to remove
     */
    function _removeAllowedERC20TokenRecipient(address token, address recipient) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (recipient == address(0)) revert InvalidRecipient();
        if (!allowedERC20TokenRecipients[token][recipient]) revert NotWhitelisted();
        
        allowedERC20TokenRecipients[token][recipient] = false;
        emit ERC20TokenRecipientAuthorized(token, recipient, false);
    }
    
    /**
     * @notice Internal function to check if recipient is authorized for ERC20 transfers
     * @dev Checks authorization: explicitly authorized recipient, smart wallet itself, or wallet owner.
     *      Checks ordered from cheapest to most expensive (storage read < address comparison < external call).
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @param token The ERC20 token address
     * @return True if recipient is authorized
     */
    function _isAuthorizedRecipient(
        address to, 
        address smartWallet,
        address token
    ) internal view virtual returns (bool) {
        if (allowedERC20TokenRecipients[token][to]) return true;
        if (to == smartWallet) return true;
        
        try ISafeWallet(smartWallet).getOwners() returns (address[] memory owners) {
            uint256 length = owners.length;
            for (uint256 i = 0; i < length;) {
                if (owners[i] == to) return true;
                unchecked { ++i; }
            }
        } catch {}
        
        return false;
    }
    
    /**
     * @notice Internal function to schedule adding a target+selector to whitelist
     * @dev Schedules whitelist addition through timelock. Validates inputs, generates salt,
     *      and schedules via TimelockController. Called by scheduleAdd batch function.
     * @param target The contract address to whitelist
     * @param selector The function selector to whitelist
     * @return operationId The unique operation ID from TimelockController
     */
    function _scheduleAdd(address target, bytes4 selector) internal returns (bytes32 operationId) {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (whitelist[target][selector]) revert AlreadyWhitelisted();
        if (opMeta[target][selector].operationId != bytes32(0)) revert PendingOperationExists();
        
        bytes32 salt = _newSalt(target, selector);
        bytes memory data = abi.encodeWithSelector(this._addToWhitelist.selector, target, selector);
        
        operationId = timelock.hashOperation(address(this), 0, data, bytes32(0), salt);
        timelock.schedule(address(this), 0, data, bytes32(0), salt, 1 days);
        
        opMeta[target][selector] = OpMeta({operationId: operationId, isAdd: true, salt: salt});
        emit TargetSelectorScheduled(operationId, target, selector, block.timestamp + 1 days);
        
        return operationId;
    }
    
    /**
     * @notice Internal function to schedule removing a target+selector from whitelist
     * @dev Schedules whitelist removal through timelock. Validates inputs, generates salt,
     *      and schedules via TimelockController. Called by scheduleRemove batch function.
     * @param target The contract address to remove from whitelist
     * @param selector The function selector to remove from whitelist
     * @return operationId The unique operation ID from TimelockController
     */
    function _scheduleRemove(address target, bytes4 selector) internal returns (bytes32 operationId) {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (!whitelist[target][selector]) revert NotWhitelisted();
        if (opMeta[target][selector].operationId != bytes32(0)) revert PendingOperationExists();
        
        bytes32 salt = _newSalt(target, selector);
        bytes memory data = abi.encodeWithSelector(this._removeFromWhitelist.selector, target, selector);
        
        operationId = timelock.hashOperation(address(this), 0, data, bytes32(0), salt);
        timelock.schedule(address(this), 0, data, bytes32(0), salt, 1 days);
        
        opMeta[target][selector] = OpMeta({operationId: operationId, isAdd: false, salt: salt});
        emit TargetSelectorScheduled(operationId, target, selector, block.timestamp + 1 days);
        
        return operationId;
    }
    
    /**
     * @notice Internal function to execute a scheduled operation after timelock expires
     * @dev Executes scheduled whitelist change via TimelockController. Uses stored metadata
     *      (not inferred state) to ensure correct operation. Called by executeOperation batch function.
     * @param target The target contract address
     * @param selector The function selector
     */
    function _executeOperation(address target, bytes4 selector) internal {
        OpMeta memory meta = opMeta[target][selector];
        require(meta.operationId != bytes32(0), "No scheduled operation");
        
        bytes memory data = meta.isAdd 
            ? abi.encodeWithSelector(this._addToWhitelist.selector, target, selector)
            : abi.encodeWithSelector(this._removeFromWhitelist.selector, target, selector);
        
        timelock.execute(address(this), 0, data, bytes32(0), meta.salt);
        delete opMeta[target][selector];
    }
    
    /**
     * @notice Internal function to cancel a pending operation before execution
     * @dev Cancels scheduled operation via TimelockController. Owner only. Called by cancelOperation batch function.
     * @param target The target contract address
     * @param selector The function selector
     */
    function _cancelOperation(address target, bytes4 selector) internal {
        OpMeta memory meta = opMeta[target][selector];
        require(meta.operationId != bytes32(0), "No scheduled operation");
        
        timelock.cancel(meta.operationId);
        delete opMeta[target][selector];
    }
    
    /**
     * @notice Add to whitelist (called by TimelockController after delay)
     * @dev Only callable by TimelockController. This is the callback function executed after timelock expires.
     * @param target The contract address to add to whitelist
     * @param selector The function selector to add to whitelist
     */
    function _addToWhitelist(address target, bytes4 selector) external {
        require(msg.sender == address(timelock), "Only timelock");
        whitelist[target][selector] = true;
        emit TargetSelectorAdded(target, selector);
    }
    
    /**
     * @notice Remove from whitelist (called by TimelockController after delay)
     * @dev Only callable by TimelockController. This is the callback function executed after timelock expires.
     * @param target The contract address to remove from whitelist
     * @param selector The function selector to remove from whitelist
     */
    function _removeFromWhitelist(address target, bytes4 selector) external {
        require(msg.sender == address(timelock), "Only timelock");
        whitelist[target][selector] = false;
        emit TargetSelectorRemoved(target, selector);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if a target+selector combination is whitelisted
     * @dev Used by GuardedExecModule to verify if target+selector is allowed to be called by session keys.
     * @param target The contract address
     * @param selector The function selector
     * @return True if whitelisted
     */
    function isWhitelisted(address target, bytes4 selector) 
        external 
        view 
        returns (bool) 
    {
        return whitelist[target][selector];
    }
    
    /**
     * @notice Get the operation ID for a scheduled operation
     * @dev Returns operation ID from stored metadata. Returns bytes32(0) if no operation scheduled.
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID, or bytes32(0) if no operation scheduled
     */
    function getOperationId(address target, bytes4 selector) 
        external 
        view 
        returns (bytes32) 
    {
        return opMeta[target][selector].operationId;
    }
    
    /**
     * @notice Check if a scheduled operation is ready to execute
     * @dev Queries TimelockController to check if timelock delay has passed and operation is executable.
     * @param target The contract address
     * @param selector The function selector
     * @return True if the operation is ready to execute
     */
    function isOperationReady(address target, bytes4 selector) 
        external 
        view 
        returns (bool) 
    {
        return timelock.isOperationReady(opMeta[target][selector].operationId);
    }
    
    /**
     * @notice Check if a scheduled operation is pending
     * @dev Queries TimelockController to check if operation is still pending (not executed/cancelled).
     * @param target The contract address
     * @param selector The function selector
     * @return True if the operation is pending
     */
    function isOperationPending(address target, bytes4 selector) 
        external 
        view 
        returns (bool) 
    {
        return timelock.isOperationPending(opMeta[target][selector].operationId);
    }
    
    /**
     * @notice Get the timestamp when a scheduled operation can be executed
     * @dev Returns execution timestamp from TimelockController. Returns 0 if no operation scheduled.
     * @param target The contract address
     * @param selector The function selector
     * @return The timestamp when the operation can be executed, or 0 if no operation scheduled
     */
    function getTimestamp(address target, bytes4 selector) 
        external 
        view 
        returns (uint256) 
    {
        return timelock.getTimestamp(opMeta[target][selector].operationId);
    }
}
