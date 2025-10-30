// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    
    /// @notice Reverse lookup: target => selector => operation ID
    mapping(address => mapping(bytes4 => bytes32)) public targetSelectorToOpId;
    
    /// @notice ERC20 tokens with transfer restrictions (e.g., USDC)
    mapping(address => bool) public allowedERC20Tokens;
    
    /// @notice Allowed recipients for specific ERC20 tokens
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
    
    event ERC20TokenRestrictionAdded(
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
        // Create TimelockController with 1 day delay
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        
        proposers[0] = address(this); // This contract can propose (owner calls through it)
        executors[0] = address(0); // Anyone can execute after timelock
        
        timelock = new TimelockController(
            1 days, // minDelay
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
     * @notice Add ERC20 token(s) to allowed list (batch operation)
     * @dev Only owner can add allowed tokens. Pass array of 1 for single token.
     * @param tokens Array of ERC20 token addresses
     */
    function addAllowedERC20Token(address[] memory tokens) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            _addAllowedERC20Token(tokens[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Remove ERC20 token(s) from allowed list (batch operation)
     * @dev Only owner can remove allowed tokens. Pass array of 1 for single token.
     * @param tokens Array of ERC20 token addresses
     */
    function removeAllowedERC20Token(address[] memory tokens) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            _removeAllowedERC20Token(tokens[i]);
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Add authorized recipient(s) for a specific ERC20 token (batch operation)
     * @dev Only owner can add authorized recipients. Token must be in allowedERC20Tokens. Pass array of 1 for single recipient.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses that will be authorized to receive the token
     */
    function addAllowedERC20TokenRecipient(address token, address[] memory recipients) external onlyOwner {
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
    function removeAllowedERC20TokenRecipient(address token, address[] memory recipients) external onlyOwner {
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
        // If token is not in allowed list, allow all transfers
        if (!allowedERC20Tokens[token]) {
            return true;
        }
        
        // For allowed tokens (with restrictions), check if `to` is authorized
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
    function scheduleAdd(address[] memory targets, bytes4[] memory selectors) 
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
    function scheduleRemove(address[] memory targets, bytes4[] memory selectors) 
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
    function executeOperation(address[] memory targets, bytes4[] memory selectors) external {
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
    function cancelOperation(address[] memory targets, bytes4[] memory selectors) external onlyOwner {
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
     * @notice Internal function to add ERC20 token to allowed list
     * @dev Internal implementation for single token addition
     * @param token The ERC20 token address
     */
    function _addAllowedERC20Token(address token) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (allowedERC20Tokens[token]) revert AlreadyWhitelisted();
        
        allowedERC20Tokens[token] = true;
        emit ERC20TokenRestrictionAdded(token, true);
    }
    
    /**
     * @notice Internal function to remove ERC20 token from allowed list
     * @dev Internal implementation for single token removal
     * @param token The ERC20 token address
     */
    function _removeAllowedERC20Token(address token) internal {
        if (token == address(0)) revert InvalidERC20Token();
        if (!allowedERC20Tokens[token]) revert NotWhitelisted();
        
        allowedERC20Tokens[token] = false;
        emit ERC20TokenRestrictionAdded(token, false);
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
        if (!allowedERC20Tokens[token]) revert NotWhitelisted(); // Token must be in allowedERC20Tokens
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
     * @param token The ERC20 token address (for checking allowedERC20TokenRecipients)
     * @return True if authorized
     */
    function _isAuthorizedRecipient(
        address to, 
        address smartWallet,
        address token
    ) internal view virtual returns (bool) {
        // Allow transfer to smart wallet itself
        if (to == smartWallet) {
            return true;
        }
        
        // Check if `to` is one of the smart wallet's owners
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
        
        // NEW: Check if `to` is an explicitly authorized recipient for this token
        if (allowedERC20TokenRecipients[token][to]) {
            return true;
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
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector)))
        );
        
        timelock.schedule(
            address(this),
            0,
            data,
            bytes32(0),
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector))),
            1 days
        );
        
        // Store reverse lookup
        targetSelectorToOpId[target][selector] = operationId;
        
        emit TargetSelectorScheduled(
            operationId,
            target,
            selector,
            block.timestamp + 1 days
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
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector)))
        );
        
        timelock.schedule(
            address(this),
            0,
            data,
            bytes32(0),
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector))),
            1 days
        );
        
        // Store reverse lookup
        targetSelectorToOpId[target][selector] = operationId;
        
        emit TargetSelectorScheduled(
            operationId,
            target,
            selector,
            block.timestamp + 1 days
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
        // Determine operation type based on current whitelist status
        bool isAdd = !whitelist[target][selector];
        bytes memory data = isAdd 
            ? abi.encodeWithSelector(this._addToWhitelist.selector, target, selector)
            : abi.encodeWithSelector(this._removeFromWhitelist.selector, target, selector);
        
        // Execute via TimelockController
        timelock.execute(
            address(this),
            0,
            data,
            bytes32(0),
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector)))
        );
    }
    
    /**
     * @notice Internal function to cancel a pending operation
     * @dev Internal implementation for single operation cancellation
     * @param target The target address
     * @param selector The selector
     */
    function _cancelOperation(address target, bytes4 selector) internal {
        bytes32 operationId = targetSelectorToOpId[target][selector];
        
        timelock.cancel(operationId);
        
        delete targetSelectorToOpId[target][selector];
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
        return targetSelectorToOpId[target][selector];
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
        bytes32 operationId = targetSelectorToOpId[target][selector];
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
        bytes32 operationId = targetSelectorToOpId[target][selector];
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
        bytes32 operationId = targetSelectorToOpId[target][selector];
        return timelock.getTimestamp(operationId);
    }
}
