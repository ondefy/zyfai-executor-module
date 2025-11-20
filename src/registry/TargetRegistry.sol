// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import { ISafeWallet } from "../interfaces/ISafeWallet.sol";

/**
 * @title TargetRegistry
 * @author ZyFAI
 * @notice Registry contract that manages whitelisting of target addresses and function selectors
 *         for secure DeFi operations. Owner can directly add/remove whitelisted targets and selectors.
 * @dev Security Features:
 *      - Pausable functionality for emergency stops
 *      - Only owner can modify whitelist
 *      - Batch operations supported for gas efficiency
 *      - ERC20 transfer recipient authorization for additional security
 *      - Two-step ownership transfer for enhanced security
 */
contract TargetRegistry is Ownable2Step, Pausable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whitelist mapping: target address => function selector => is whitelisted
     * @dev Stores whether target+selector combinations are whitelisted. Only owner can modify.
     *
     * Example: whitelist[uniswapRouter][swap.selector] = true means swap() on Uniswap
     *      router is allowed to be called by session keys via the executor module.
     */
    mapping(address => mapping(bytes4 => bool)) public whitelist;

    /**
     * @notice Counter for number of whitelisted selectors per target address
     * @dev Tracks how many selectors are whitelisted for each target. Used to efficiently
     *      determine if a target is whitelisted (counter > 0). Updated automatically when
     *      selectors are added/removed.
     */
    mapping(address => uint256) public whitelistedSelectorCount;

    /**
     * @notice Mapping to track which addresses are whitelisted targets
     * @dev Set to true when a target has at least one whitelisted selector (counter > 0).
     *      Used for efficient checking if an address is a whitelisted target (for approve validation).
     *      Updated automatically when selectors are added/removed.
     */
    mapping(address => bool) public whitelistedTargets;

    /**
     * @notice Mapping of authorized ERC20 token recipients: token => recipient => is allowed
     * @dev Controls which addresses can receive ERC20 tokens. Transfers allowed to: wallet itself,
     * wallet owners, or authorized recipients.
     */
    mapping(address => mapping(address => bool)) public allowedERC20TokenRecipients;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a target+selector combination is added to the whitelist
     * @param target The target contract address that was whitelisted
     * @param selector The function selector that was whitelisted
     */
    event TargetSelectorAdded(address indexed target, bytes4 indexed selector);

    /**
     * @notice Emitted when a target+selector combination is removed from the whitelist
     * @param target The target contract address that was removed
     * @param selector The function selector that was removed
     */
    event TargetSelectorRemoved(address indexed target, bytes4 indexed selector);

    /**
     * @notice Emitted when an ERC20 token recipient authorization is added or removed
     * @param token The ERC20 token address
     * @param recipient The recipient address being authorized or deauthorized
     * @param authorized True if authorized, false if deauthorized
     */
    event ERC20TokenRecipientAuthorized(
        address indexed token, address indexed recipient, bool authorized
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
     * @notice Initialize registry
     * @param admin The address that will own this contract (should be multisig for production)
     */
    constructor(address admin) Ownable(admin) {}

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause the registry (emergency stop)
     * @dev Blocks addToWhitelist and removeFromWhitelist when paused.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the registry
     * @dev Resumes normal operation, allowing whitelist modifications again.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Add target+selector(s) to whitelist (batch operation)
     * @dev Owner only. Immediate operation. Reverts if contract is paused.
     * @param targets Array of contract addresses to whitelist
     * @param selectors Array of function selectors to whitelist
     */
    function addToWhitelist(
        address[] calldata targets,
        bytes4[] calldata selectors
    )
        external
        onlyOwner
        whenNotPaused
    {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != selectors.length) revert LengthMismatch();

        for (uint256 i = 0; i < length;) {
            _addToWhitelist(targets[i], selectors[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove target+selector(s) from whitelist (batch operation)
     * @dev Owner only. Immediate operation. Reverts if contract is paused.
     * @param targets Array of contract addresses to remove from whitelist
     * @param selectors Array of function selectors to remove from whitelist
     */
    function removeFromWhitelist(
        address[] calldata targets,
        bytes4[] calldata selectors
    )
        external
        onlyOwner
        whenNotPaused
    {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != selectors.length) revert LengthMismatch();

        for (uint256 i = 0; i < length;) {
            _removeFromWhitelist(targets[i], selectors[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Add authorized recipient(s) for a specific ERC20 token (batch operation)
     * @dev Owner only. Immediate operation. Reverts if contract is paused. Authorizes recipients for ERC20
     * transfers.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses to authorize
     */
    function addAllowedERC20TokenRecipient(
        address token,
        address[] calldata recipients
    )
        external
        onlyOwner
        whenNotPaused
    {
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length;) {
            _addAllowedERC20TokenRecipient(token, recipients[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove authorized recipient(s) for a specific ERC20 token (batch operation)
     * @dev Owner only. Immediate operation. Reverts if contract is paused. Removes recipient authorization.
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses to remove
     */
    function removeAllowedERC20TokenRecipient(
        address token,
        address[] calldata recipients
    )
        external
        onlyOwner
        whenNotPaused
    {
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length;) {
            _removeAllowedERC20TokenRecipient(token, recipients[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Check if an ERC20 transfer to a specific recipient is authorized
     * @dev Called by GuardedExecModule. Authorized if recipient is: explicitly authorized, wallet
     * itself, or wallet owner.
     * @param token The ERC20 token address
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @return True if the transfer is authorized
     */
    function isERC20TransferAuthorized(
        address token,
        address to,
        address smartWallet
    )
        external
        view
        returns (bool)
    {
        return _isAuthorizedRecipient(to, smartWallet, token);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to add a target+selector to whitelist
     * @dev Validates inputs and updates whitelist state. Called by addToWhitelist batch function.
     * @param target The contract address to whitelist
     * @param selector The function selector to whitelist
     */
    function _addToWhitelist(address target, bytes4 selector) internal {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();

        // Validate state: prevent redundant operations
        if (whitelist[target][selector]) {
            revert AlreadyWhitelisted();
        }

        whitelist[target][selector] = true;
        unchecked {
            whitelistedSelectorCount[target]++;
        }
        whitelistedTargets[target] = true; // Mark target as whitelisted

        emit TargetSelectorAdded(target, selector);
    }

    /**
     * @notice Internal function to remove a target+selector from whitelist
     * @dev Validates inputs and updates whitelist state. Called by removeFromWhitelist batch function.
     * @param target The contract address to remove from whitelist
     * @param selector The function selector to remove from whitelist
     */
    function _removeFromWhitelist(address target, bytes4 selector) internal {
        if (target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();

        // Validate state: prevent redundant operations
        if (!whitelist[target][selector]) {
            revert NotWhitelisted();
        }

        whitelist[target][selector] = false;
        unchecked {
            whitelistedSelectorCount[target]--;
        }

        // If counter reaches zero, mark target as no longer whitelisted
        if (whitelistedSelectorCount[target] == 0) {
            whitelistedTargets[target] = false;
        }

        emit TargetSelectorRemoved(target, selector);
    }

    /**
     * @notice Internal function to add authorized recipient for ERC20 token
     * @dev Validates inputs and authorizes recipient. Called by addAllowedERC20TokenRecipient batch
     * function.
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
     * @dev Validates inputs and removes recipient authorization. Called by
     * removeAllowedERC20TokenRecipient batch function.
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
     * @dev Checks authorization: explicitly authorized recipient, smart wallet itself, or wallet
     * owner.
     *      Checks ordered from cheapest to most expensive (storage read < address comparison <
     * external call).
     * @param to The recipient address
     * @param smartWallet The smart wallet address
     * @param token The ERC20 token address
     * @return True if recipient is authorized
     */
    function _isAuthorizedRecipient(
        address to,
        address smartWallet,
        address token
    )
        internal
        view
        virtual
        returns (bool)
    {
        if (allowedERC20TokenRecipients[token][to]) return true;
        if (to == smartWallet) return true;

        try ISafeWallet(smartWallet).getOwners() returns (address[] memory owners) {
            uint256 length = owners.length;
            for (uint256 i = 0; i < length;) {
                if (owners[i] == to) return true;
                unchecked {
                    ++i;
                }
            }
        } catch { }

        return false;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a target+selector combination is whitelisted
     * @dev Used by GuardedExecModule to verify if target+selector is allowed to be called by
     * session keys.
     * @param target The contract address
     * @param selector The function selector
     * @return True if whitelisted
     */
    function isWhitelisted(address target, bytes4 selector) external view returns (bool) {
        return whitelist[target][selector];
    }

    /**
     * @notice Check if a target address has any whitelisted selector
     * @dev Used to verify if an address is a whitelisted target contract (for approve validation).
     *      Returns true if the target has at least one whitelisted selector, indicating it's a trusted contract.
     * @param target The contract address to check
     * @return True if the target is whitelisted (has at least one whitelisted selector)
     */
    function isWhitelistedTarget(address target) external view returns (bool) {
        return whitelistedTargets[target];
    }
}
