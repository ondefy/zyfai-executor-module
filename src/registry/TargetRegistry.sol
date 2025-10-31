// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import { ISafeWallet } from "../interfaces/ISafeWallet.sol";

/**
 * @title TargetRegistry
 * @author Zyfi
 * @notice Registry using OpenZeppelin's TimelockController for battle-tested timelock
 * @dev Integrates with OZ TimelockController for proven security and reliability
 *      Pausable functionality protects against compromised owner wallet
 */
contract TargetRegistry is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice OpenZeppelin TimelockController (1 day delay)
    TimelockController public immutable timelock;
    
    /// @notice Whitelist: target address => selector => is whitelisted
    mapping(address => mapping(bytes4 => bool)) public whitelist;
    
    /// @notice Operation metadata for each target+selector
    /// @dev Stores operation ID, action type, and unique salt for re-scheduling
    struct OpMeta {
        bytes32 operationId;
        bool isAdd;
        bytes32 salt;
    }
    mapping(address => mapping(bytes4 => OpMeta)) public opMeta;
    
    /// @notice ERC20 tokens with restricted transfers (e.g., USDC)
    /// @dev When true, transfers to arbitrary addresses are blocked; only authorized recipients allowed
    mapping(address => bool) public restrictedERC20Tokens;
    
    /// @notice Authorized recipients for specific ERC20 tokens
    /// @dev For restricted tokens, this maps: token => recipient => is allowed
    mapping(address => mapping(address => bool)) public allowedERC20TokenRecipients;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TargetSelectorScheduled(
        bytes32 indexed operationId,
        address indexed target,
        bytes4 indexed selector,
        uint256 executeAfter
    );
    
    event TargetSelectorAdded(
        address indexed target,
        bytes4 indexed selector
    );
    
    event TargetSelectorRemoved(
        address indexed target,
        bytes4 indexed selector
    );
    
    event RestrictedERC20TokenChanged(
        address indexed token,
        bool restricted
    );
    
    event ERC20TokenRecipientAuthorized(
        address indexed token,
        address indexed recipient,
        bool authorized
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidTarget();
    error InvalidSelector();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error PendingOperationExists();
    error UnauthorizedERC20Transfer(address token, address to);
    error InvalidERC20Token();
    error InvalidRecipient();
    error EmptyBatch();
    error LengthMismatch();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize registry with OpenZeppelin TimelockController
     * @param admin Address that can schedule operations (should be multisig)
     */
    constructor(address admin) Ownable(admin) {
        // Create TimelockController with 1 minute delay
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        
        proposers[0] = address(this); // This contract can propose (owner calls through it)
        executors[0] = address(0); // Anyone can execute after timelock
        
        timelock = new TimelockController(
            1 minutes, // minDelay
            proposers,
            executors,
            address(0) // No admin (immutable roles)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Pause the registry (emergency stop)
     * @dev Prevents scheduling new operations
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the registry
     * @dev Allows scheduling operations again
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Add ERC20 token(s) to restricted list (batch operation)
     * @dev Owner only. Enables transfer monitoring. Pass array of 1 for single token.
     * @param tokens Array of ERC20 token addresses
     */
    function addRestrictedERC20Token(address[] calldata tokens) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            _addRestrictedERC20Token(tokens[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Remove ERC20 token(s) from restricted list (batch operation)
     * @dev Owner only. Disables transfer monitoring. Pass array of 1 for single token.
     * @param tokens Array of ERC20 token addresses
     */
    function removeRestrictedERC20Token(address[] calldata tokens) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            _removeRestrictedERC20Token(tokens[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Add authorized recipient(s) for a specific ERC20 token (batch operation)
     * @dev Owner only. Token must be in restrictedERC20Tokens. Pass array of 1 for single recipient.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses that will be authorized to receive the token
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
     * @dev Only owner can remove authorized recipients. Pass array of 1 for single recipient.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses to remove from authorized list
     */
    function removeAllowedERC20TokenRecipient(address token, address[] calldata recipients) external onlyOwner {
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length;) {
            _removeAllowedERC20TokenRecipient(token, recipients[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Check if ERC20 transfer is authorized for restricted tokens
     * @dev For restricted tokens, `to` must be smart wallet, one of its owners, or an explicitly authorized recipient
     * @param token The ERC20 token address
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @return True if transfer is authorized
     */
    function isERC20TransferAuthorized(
        address token,
        address to,
        address smartWallet
    ) external view returns (bool) {
        // If token is not in restricted list, allow all transfers
        if (!restrictedERC20Tokens[token]) {
            return true;
        }
        
        // For restricted tokens, check if `to` is authorized
        // Pass token parameter to check allowedERC20TokenRecipients
        return _isAuthorizedRecipient(to, smartWallet, token);
    }
    
    /**
     * @notice Schedule adding target+selector(s) to whitelist (batch operation)
     * @dev Can only be called when not paused. Pass array of 1 for single operation.
     * @param targets Array of contract addresses
     * @param selectors Array of function selectors
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
     * @dev Can only be called when not paused. Pass array of 1 for single operation.
     * @param targets Array of contract addresses
     * @param selectors Array of function selectors
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
     * @notice Execute scheduled operation(s) (batch operation)
     * @dev Anyone can call after timelock. Pass array of 1 for single operation.
     * @param targets Array of target addresses
     * @param selectors Array of selectors
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
     * @notice Cancel pending operation(s) (batch operation)
     * @dev Only owner can cancel. Pass array of 1 for single operation.
     * @param targets Array of target addresses
     * @param selectors Array of selectors
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
     * @dev Combines target, selector, timestamp, and block randomness for uniqueness
     * @param target The target address
     * @param selector The function selector
     * @return Unique salt for timelock operation
     */
    function _newSalt(address target, bytes4 selector) internal view returns (bytes32) {
        // Use target, selector, timestamp, and block.prevrandao for uniqueness
        // This allows re-scheduling the same (target, selector) pair multiple times
        return keccak256(abi.encodePacked(target, selector, block.timestamp, block.prevrandao));
    }
    
    /**
     * @notice Internal function to add ERC20 token to restricted list
     * @dev Internal implementation for single token addition
     * @param token The ERC20 token address
     */
    function _addRestrictedERC20Token(address token) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (restrictedERC20Tokens[token]) revert AlreadyWhitelisted();
        
        restrictedERC20Tokens[token] = true;
        emit RestrictedERC20TokenChanged(token, true);
    }
    
    /**
     * @notice Internal function to remove ERC20 token from restricted list
     * @dev Internal implementation for single token removal
     * @param token The ERC20 token address
     */
    function _removeRestrictedERC20Token(address token) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (!restrictedERC20Tokens[token]) revert NotWhitelisted();
        
        restrictedERC20Tokens[token] = false;
        emit RestrictedERC20TokenChanged(token, false);
    }
    
    /**
     * @notice Internal function to add authorized recipient for ERC20 token
     * @dev Internal implementation for single recipient addition
     * @param token The ERC20 token address
     * @param recipient The recipient address
     */
    function _addAllowedERC20TokenRecipient(address token, address recipient) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (recipient == address(0)) revert InvalidRecipient();
        if (!restrictedERC20Tokens[token]) revert NotWhitelisted(); // Token must be in restrictedERC20Tokens
        if (allowedERC20TokenRecipients[token][recipient]) revert AlreadyWhitelisted();
        
        allowedERC20TokenRecipients[token][recipient] = true;
        emit ERC20TokenRecipientAuthorized(token, recipient, true);
    }
    
    /**
     * @notice Internal function to remove authorized recipient for ERC20 token
     * @dev Internal implementation for single recipient removal
     * @param token The ERC20 token address
     * @param recipient The recipient address
     */
    function _removeAllowedERC20TokenRecipient(address token, address recipient) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (recipient == address(0)) revert InvalidRecipient();
        if (!allowedERC20TokenRecipients[token][recipient]) revert NotWhitelisted();
        
        allowedERC20TokenRecipients[token][recipient] = false;
        emit ERC20TokenRecipientAuthorized(token, recipient, false);
    }
    
    /**
     * @notice Internal function to check if recipient is authorized
     * @dev Checks if `to` is the smart wallet itself, one of its owners, or an explicitly authorized recipient
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @param token The ERC20 token address (for checking allowedERC20TokenRecipients for restricted tokens)
     * @return True if authorized
     */
    function _isAuthorizedRecipient(
        address to, 
        address smartWallet,
        address token
    ) internal view virtual returns (bool) {
        // Check if `to` is an explicitly authorized recipient for this token (cheapest check first)
        if (allowedERC20TokenRecipients[token][to]) {
            return true;
        }
        
        // Allow transfer to smart wallet itself
        if (to == smartWallet) {
            return true;
        }
        
        // Check if `to` is one of the smart wallet's owners (external call, more expensive)
        try ISafeWallet(smartWallet).getOwners() returns (address[] memory owners) {
            uint256 length = owners.length; // Cache length for gas savings
            for (uint256 i = 0; i < length;) {
                if (owners[i] == to) {
                    return true;
                }
                unchecked { ++i; } // Safe: i < length, cannot overflow
            }
        } catch {
            // If getOwners() fails, continue to next check
        }
        
        return false;
    }
    
    /**
     * @notice Internal function to schedule adding a target+selector to whitelist
     * @dev Internal implementation for single operation scheduling
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID from TimelockController
     */
    function _scheduleAdd(address target, bytes4 selector) internal returns (bytes32 operationId) {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (whitelist[target][selector]) revert AlreadyWhitelisted();
        if (opMeta[target][selector].operationId != bytes32(0)) revert PendingOperationExists();
        
        // Generate unique salt for this operation
        bytes32 salt = _newSalt(target, selector);
        
        // Prepare the call to _addToWhitelist
        bytes memory data = abi.encodeWithSelector(
            this._addToWhitelist.selector,
            target,
            selector
        );
        
        // Schedule via TimelockController
        operationId = timelock.hashOperation(
            address(this),
            0,
            data,
            bytes32(0),
            salt
        );
        
        timelock.schedule(
            address(this),
            0,
            data,
            bytes32(0),
            salt,
            1 minutes
        );
        
        // Store operation metadata (for execution and re-scheduling)
        opMeta[target][selector] = OpMeta({
            operationId: operationId,
            isAdd: true,
            salt: salt
        });
        
        emit TargetSelectorScheduled(
            operationId,
            target,
            selector,
            block.timestamp + 1 minutes
        );
        
        return operationId;
    }
    
    /**
     * @notice Internal function to schedule removing a target+selector from whitelist
     * @dev Internal implementation for single operation scheduling
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID from TimelockController
     */
    function _scheduleRemove(address target, bytes4 selector) internal returns (bytes32 operationId) {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (!whitelist[target][selector]) revert NotWhitelisted();
        if (opMeta[target][selector].operationId != bytes32(0)) revert PendingOperationExists();
        
        // Generate unique salt for this operation
        bytes32 salt = _newSalt(target, selector);
        
        // Prepare the call to _removeFromWhitelist
        bytes memory data = abi.encodeWithSelector(
            this._removeFromWhitelist.selector,
            target,
            selector
        );
        
        // Schedule via TimelockController
        operationId = timelock.hashOperation(
            address(this),
            0,
            data,
            bytes32(0),
            salt
        );
        
        timelock.schedule(
            address(this),
            0,
            data,
            bytes32(0),
            salt,
            1 minutes
        );
        
        // Store operation metadata (for execution and re-scheduling)
        opMeta[target][selector] = OpMeta({
            operationId: operationId,
            isAdd: false,
            salt: salt
        });
        
        emit TargetSelectorScheduled(
            operationId,
            target,
            selector,
            block.timestamp + 1 minutes
        );
        
        return operationId;
    }
    
    /**
     * @notice Internal function to execute a scheduled operation
     * @dev Internal implementation for single operation execution
     * @param target The target address
     * @param selector The selector
     */
    function _executeOperation(address target, bytes4 selector) internal {
        // Get stored operation metadata (don't infer from current state!)
        OpMeta memory meta = opMeta[target][selector];
        require(meta.operationId != bytes32(0), "No scheduled operation");
        
        // Prepare data based on stored operation type
        bytes memory data = meta.isAdd 
            ? abi.encodeWithSelector(this._addToWhitelist.selector, target, selector)
            : abi.encodeWithSelector(this._removeFromWhitelist.selector, target, selector);
        
        // Execute via TimelockController with stored operation ID and salt
        timelock.execute(
            address(this),
            0,
            data,
            bytes32(0),
            meta.salt
        );
        
        // Clear metadata to allow future re-scheduling of this (target, selector)
        delete opMeta[target][selector];
    }
    
    /**
     * @notice Internal function to cancel a pending operation
     * @dev Internal implementation for single operation cancellation
     * @param target The target address
     * @param selector The selector
     */
    function _cancelOperation(address target, bytes4 selector) internal {
        OpMeta memory meta = opMeta[target][selector];
        require(meta.operationId != bytes32(0), "No scheduled operation");
        
        timelock.cancel(meta.operationId);
        
        // Clear metadata to allow future re-scheduling
        delete opMeta[target][selector];
    }
    
    /**
     * @notice Internal function to add to whitelist (called by TimelockController)
     * @dev Only callable by the TimelockController after timelock expires
     */
    function _addToWhitelist(address target, bytes4 selector) external {
        require(msg.sender == address(timelock), "Only timelock");
        whitelist[target][selector] = true;
        emit TargetSelectorAdded(target, selector);
    }
    
    /**
     * @notice Internal function to remove from whitelist (called by TimelockController)
     * @dev Only callable by the TimelockController after timelock expires
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
     * @notice Get the operation ID for a target+selector
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID
     */
    function getOperationId(address target, bytes4 selector) 
        external 
        view 
        returns (bytes32) 
    {
        return opMeta[target][selector].operationId;
    }
    
    /**
     * @notice Check if an operation is ready to execute
     * @param target The contract address
     * @param selector The function selector
     * @return True if ready
     */
    function isOperationReady(address target, bytes4 selector) 
        external 
        view 
        returns (bool) 
    {
        bytes32 operationId = opMeta[target][selector].operationId;
        return timelock.isOperationReady(operationId);
    }
    
    /**
     * @notice Check if an operation is pending
     * @param target The contract address
     * @param selector The function selector
     * @return True if pending
     */
    function isOperationPending(address target, bytes4 selector) 
        external 
        view 
        returns (bool) 
    {
        bytes32 operationId = opMeta[target][selector].operationId;
        return timelock.isOperationPending(operationId);
    }
    
    /**
     * @notice Get the timestamp when operation can be executed
     * @param target The contract address
     * @param selector The function selector
     * @return Timestamp when ready
     */
    function getTimestamp(address target, bytes4 selector) 
        external 
        view 
        returns (uint256) 
    {
        bytes32 operationId = opMeta[target][selector].operationId;
        return timelock.getTimestamp(operationId);
    }
}
