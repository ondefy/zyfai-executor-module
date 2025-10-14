// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title TargetRegistry
 * @author Zyfi
 * @notice Enhanced registry for whitelisting DeFi protocol targets with function selectors and timelock
 * @dev Features:
 *      - Target + Selector whitelisting (not just target address)
 *      - 1-day timelock for adding/removing entries
 *      - Staged updates (schedule → execute after timelock)
 */
contract TargetRegistry {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum OperationType {
        ADD,
        REMOVE
    }
    
    struct PendingOperation {
        address target;
        bytes4 selector;
        OperationType opType;
        uint256 executeAfter;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Owner of the registry (can schedule operations)
    address public owner;
    
    /// @notice Timelock duration (1 day)
    uint256 public constant TIMELOCK_DURATION = 1 days;
    
    /// @notice Whitelist: target address => selector => is whitelisted
    mapping(address => mapping(bytes4 => bool)) public whitelist;
    
    /// @notice Pending operations indexed by operation ID
    mapping(bytes32 => PendingOperation) public pendingOperations;
    
    /// @notice Reverse lookup: target => selector => operation ID (for easy opId retrieval)
    mapping(address => mapping(bytes4 => bytes32)) public targetSelectorToOpId;
    
    /// @notice Counter for generating unique operation IDs
    uint256 private operationCounter;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OperationScheduled(
        bytes32 indexed operationId,
        address indexed target,
        bytes4 indexed selector,
        OperationType opType,
        uint256 executeAfter
    );
    
    event OperationExecuted(
        bytes32 indexed operationId,
        address indexed target,
        bytes4 indexed selector,
        OperationType opType
    );
    
    event OperationCancelled(
        bytes32 indexed operationId,
        address indexed target,
        bytes4 indexed selector
    );
    
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error OnlyOwner();
    error InvalidTarget();
    error InvalidSelector();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error OperationAlreadyScheduled();
    error OperationNotFound();
    error OperationAlreadyExecuted();
    error TimelockNotExpired();
    error InvalidOperation();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize the registry with an owner
     * @param _owner Address that can schedule operations
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidTarget();
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    /*//////////////////////////////////////////////////////////////
                          SCHEDULING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Schedule adding a target+selector to the whitelist
     * @param target The contract address to whitelist
     * @param selector The function selector to whitelist
     * @return operationId Unique ID for this operation
     */
    function scheduleAdd(address target, bytes4 selector) 
        external 
        onlyOwner 
        returns (bytes32 operationId) 
    {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (whitelist[target][selector]) revert AlreadyWhitelisted();
        
        operationId = _generateOperationId(target, selector, OperationType.ADD);
        
        if (pendingOperations[operationId].executeAfter != 0) {
            revert OperationAlreadyScheduled();
        }
        
        uint256 executeAfter = block.timestamp + TIMELOCK_DURATION;
        
        pendingOperations[operationId] = PendingOperation({
            target: target,
            selector: selector,
            opType: OperationType.ADD,
            executeAfter: executeAfter,
            executed: false
        });
        
        // Store reverse lookup for easy opId retrieval
        targetSelectorToOpId[target][selector] = operationId;
        
        emit OperationScheduled(
            operationId,
            target,
            selector,
            OperationType.ADD,
            executeAfter
        );
        
        return operationId;
    }
    
    /**
     * @notice Schedule removing a target+selector from the whitelist
     * @param target The contract address to remove
     * @param selector The function selector to remove
     * @return operationId Unique ID for this operation
     */
    function scheduleRemove(address target, bytes4 selector) 
        external 
        onlyOwner 
        returns (bytes32 operationId) 
    {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (!whitelist[target][selector]) revert NotWhitelisted();
        
        operationId = _generateOperationId(target, selector, OperationType.REMOVE);
        
        if (pendingOperations[operationId].executeAfter != 0) {
            revert OperationAlreadyScheduled();
        }
        
        uint256 executeAfter = block.timestamp + TIMELOCK_DURATION;
        
        pendingOperations[operationId] = PendingOperation({
            target: target,
            selector: selector,
            opType: OperationType.REMOVE,
            executeAfter: executeAfter,
            executed: false
        });
        
        // Store reverse lookup for easy opId retrieval
        targetSelectorToOpId[target][selector] = operationId;
        
        emit OperationScheduled(
            operationId,
            target,
            selector,
            OperationType.REMOVE,
            executeAfter
        );
        
        return operationId;
    }

    /*//////////////////////////////////////////////////////////////
                          EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Execute a pending operation after timelock expires
     * @param operationId The ID of the operation to execute
     */
    function executeOperation(bytes32 operationId) external {
        PendingOperation storage op = pendingOperations[operationId];
        
        if (op.executeAfter == 0) revert OperationNotFound();
        if (op.executed) revert OperationAlreadyExecuted();
        if (block.timestamp < op.executeAfter) revert TimelockNotExpired();
        
        op.executed = true;
        
        if (op.opType == OperationType.ADD) {
            whitelist[op.target][op.selector] = true;
        } else if (op.opType == OperationType.REMOVE) {
            whitelist[op.target][op.selector] = false;
        } else {
            revert InvalidOperation();
        }
        
        emit OperationExecuted(
            operationId,
            op.target,
            op.selector,
            op.opType
        );
    }
    
    /**
     * @notice Cancel a pending operation
     * @param operationId The ID of the operation to cancel
     */
    function cancelOperation(bytes32 operationId) external onlyOwner {
        PendingOperation storage op = pendingOperations[operationId];
        
        if (op.executeAfter == 0) revert OperationNotFound();
        if (op.executed) revert OperationAlreadyExecuted();
        
        emit OperationCancelled(operationId, op.target, op.selector);
        
        delete pendingOperations[operationId];
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
     * @notice Get the operation ID for a target+selector combination
     * @dev Useful for finding the opId to execute after timelock
     * @param target The contract address
     * @param selector The function selector
     * @return operationId The operation ID (bytes32(0) if not found)
     */
    function getOperationId(address target, bytes4 selector) 
        external 
        view 
        returns (bytes32) 
    {
        return targetSelectorToOpId[target][selector];
    }
    
    /**
     * @notice Get details of a pending operation
     * @param operationId The operation ID
     * @return operation The pending operation details
     */
    function getPendingOperation(bytes32 operationId) 
        external 
        view 
        returns (PendingOperation memory) 
    {
        return pendingOperations[operationId];
    }
    
    /**
     * @notice Check if an operation can be executed
     * @param operationId The operation ID
     * @return True if ready to execute
     */
    function canExecute(bytes32 operationId) external view returns (bool) {
        PendingOperation storage op = pendingOperations[operationId];
        return op.executeAfter != 0 
            && !op.executed 
            && block.timestamp >= op.executeAfter;
    }
    
    /**
     * @notice Get remaining time until operation can be executed
     * @param operationId The operation ID
     * @return Seconds remaining (0 if ready or invalid)
     */
    function getTimeRemaining(bytes32 operationId) 
        external 
        view 
        returns (uint256) 
    {
        PendingOperation storage op = pendingOperations[operationId];
        if (op.executeAfter == 0 || op.executed) return 0;
        if (block.timestamp >= op.executeAfter) return 0;
        return op.executeAfter - block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Transfer ownership of the registry
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidTarget();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Generate a unique operation ID
     * @param target The target address
     * @param selector The function selector
     * @param opType The operation type
     * @return Unique operation ID
     */
    function _generateOperationId(
        address target,
        bytes4 selector,
        OperationType opType
    ) internal returns (bytes32) {
        operationCounter++;
        return keccak256(
            abi.encodePacked(
                target,
                selector,
                opType,
                operationCounter,
                block.timestamp
            )
        );
    }
}
