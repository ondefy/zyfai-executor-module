// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISafeWallet } from "./interfaces/ISafeWallet.sol";

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
    mapping(address => bool) public restrictedERC20Tokens;

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

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidTarget();
    error InvalidSelector();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error UnauthorizedERC20Transfer(address token, address to);
    error InvalidERC20Token();

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
                          PAUSE FUNCTIONS
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

    /*//////////////////////////////////////////////////////////////
                        ERC20 RESTRICTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add ERC20 token to restricted list (e.g., USDC)
     * @dev Only owner can add restricted tokens
     * @param token The ERC20 token address
     */
    function addRestrictedERC20Token(address token) external onlyOwner {
        if (token == address(0)) revert InvalidERC20Token();
        if (restrictedERC20Tokens[token]) revert AlreadyWhitelisted();
        
        restrictedERC20Tokens[token] = true;
        emit ERC20TokenRestrictionAdded(token, true);
    }
    
    /**
     * @notice Remove ERC20 token from restricted list
     * @dev Only owner can remove restricted tokens
     * @param token The ERC20 token address
     */
    function removeRestrictedERC20Token(address token) external onlyOwner {
        if (token == address(0)) revert InvalidERC20Token();
        if (!restrictedERC20Tokens[token]) revert NotWhitelisted();
        
        restrictedERC20Tokens[token] = false;
        emit ERC20TokenRestrictionAdded(token, false);
    }
    
    /**
     * @notice Check if ERC20 transfer is authorized for restricted tokens
     * @dev For restricted tokens, `to` must be smart wallet or one of its owners
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
        // If token is not restricted, allow all transfers
        if (!restrictedERC20Tokens[token]) {
            return true;
        }
        
        // // For restricted tokens, check if `to` is authorized
        return _isAuthorizedRecipient(to, smartWallet);
    }
    
    /**
     * @notice Internal function to check if recipient is authorized
     * @dev Checks if `to` is the smart wallet itself or one of its owners
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @return True if authorized
     */
    function _isAuthorizedRecipient(address to, address smartWallet) 
        internal 
        view 
        virtual
        returns (bool) 
    {
        // Allow transfer to smart wallet itself
        if (to == smartWallet) {
            return true;
        }
        
        // Check if `to` is one of the smart wallet's owners
        try ISafeWallet(smartWallet).getOwners() returns (address[] memory owners) {
            for (uint256 i = 0; i < owners.length; i++) {
                if (owners[i] == to) {
                    return true;
                }
            }
        } catch {
            // If getOwners() fails, only allow transfer to smart wallet itself
            return false;
        }
        
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                          SCHEDULING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Schedule adding a target+selector to whitelist (via TimelockController)
     * @dev Can only be called when not paused (protection against compromised owner)
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID from TimelockController
     */
    function scheduleAdd(address target, bytes4 selector) 
        external 
        onlyOwner 
        whenNotPaused
        returns (bytes32 operationId) 
    {
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
            address(this), // target
            0, // value
            data, // data
            bytes32(0), // predecessor
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector))) // salt (unique per target+selector)
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
     * @notice Schedule removing a target+selector from whitelist
     * @dev Can only be called when not paused (protection against compromised owner)
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID from TimelockController
     */
    function scheduleRemove(address target, bytes4 selector) 
        external 
        onlyOwner 
        whenNotPaused
        returns (bytes32 operationId) 
    {
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

    /*//////////////////////////////////////////////////////////////
                          EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Execute a scheduled operation (anyone can call after timelock)
     * @param target The target address
     * @param selector The selector
     */
    function executeOperation(address target, bytes4 selector) external {
        // Determine operation type based on current whitelist status
        bool isAdd = !whitelist[target][selector];
        bytes memory data = isAdd 
            ? abi.encodeWithSelector(this._addToWhitelist.selector, target, selector)
            : abi.encodeWithSelector(this._removeFromWhitelist.selector, target, selector);
        
        // Execute via TimelockController
        // Note: TimelockController calculates the operationId internally
        timelock.execute(
            address(this),
            0,
            data,
            bytes32(0),
            bytes32(uint256(uint160(target)) ^ uint256(uint32(selector)))
        );
    }
    
    /**
     * @notice Cancel a pending operation
     * @param target The target address
     * @param selector The selector
     */
    function cancelOperation(address target, bytes4 selector) external onlyOwner {
        bytes32 operationId = targetSelectorToOpId[target][selector];
        
        timelock.cancel(operationId);
        
        delete targetSelectorToOpId[target][selector];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
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

