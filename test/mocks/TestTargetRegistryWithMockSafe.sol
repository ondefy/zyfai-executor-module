// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TargetRegistry } from "src/registry/TargetRegistry.sol";
import { MockSafeWallet } from "./MockSafeWallet.sol";

/**
 * @title TestTargetRegistryWithMockSafe
 * @author ZyFAI
 * @notice Test registry contract that uses mock Safe wallet for testing purposes - NOT for production use
 * @dev Extends TargetRegistry and overrides _isAuthorizedRecipient to use MockSafeWallet.getOwners()
 *      instead of the ISafeWallet interface. Used in tests to verify ERC20 transfer authorization logic.
 */
contract TestTargetRegistryWithMockSafe is TargetRegistry {
    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Mock Safe wallet instance used for getOwners() calls
     * @dev Used instead of actual ISafeWallet interface for testing
     */
    MockSafeWallet public mockSafeWallet;
    
    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Constructor for test registry with mock Safe wallet
     * @param admin Address of the admin (timelock controller)
     * @param _mockSafeWallet Address of the MockSafeWallet contract
     */
    constructor(address admin, address _mockSafeWallet) TargetRegistry(admin) {
        mockSafeWallet = MockSafeWallet(_mockSafeWallet);
    }
    
    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Override to use mock Safe wallet instead of actual ISafeWallet interface
     * @dev Checks ERC20 transfer authorization in order from cheapest to most expensive:
     *      1. Explicitly authorized recipient (storage read - cheapest)
     *      2. Smart wallet itself (address comparison)
     *      3. Wallet owner via mockSafeWallet.getOwners() (external call - most expensive)
     *      
     *      This order matches the original TargetRegistry implementation for gas optimization.
     *      Uses try-catch to gracefully handle any failures in the external call.
     * @param to The recipient address to check authorization for
     * @param smartWallet The smart wallet address
     * @param token The ERC20 token address
     * @return True if recipient is authorized to receive ERC20 transfers
     */
    function _isAuthorizedRecipient(
        address to,
        address smartWallet,
        address token
    ) internal view override returns (bool) {
        // Check 1: Explicitly authorized recipient (cheapest - storage read)
        if (allowedERC20TokenRecipients[token][to]) return true;
        
        // Check 2: Smart wallet itself (address comparison)
        if (to == smartWallet) return true;
        
        // Check 3: Wallet owner (most expensive - external call)
        // Uses try-catch to handle any potential failures gracefully
        try mockSafeWallet.getOwners() returns (address[] memory owners) {
            uint256 length = owners.length;
            for (uint256 i = 0; i < length;) {
                if (owners[i] == to) return true;
                unchecked { ++i; }
            }
        } catch {
            // Gracefully handle any failures in the external call
        }
        
        return false;
    }
}

