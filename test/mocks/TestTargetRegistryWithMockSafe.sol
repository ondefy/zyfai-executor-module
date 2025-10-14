// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TargetRegistry } from "src/unified-approach/TargetRegistry.sol";
import { MockSafeWallet } from "./MockSafeWallet.sol";

/**
 * @title TestTargetRegistryWithMockSafe
 * @notice Test registry that uses mock Safe wallet for getOwners() calls
 */
contract TestTargetRegistryWithMockSafe is TargetRegistry {
    MockSafeWallet public mockSafeWallet;
    
    constructor(address admin, address _mockSafeWallet) TargetRegistry(admin) {
        mockSafeWallet = MockSafeWallet(_mockSafeWallet);
    }
    
    function _isAuthorizedRecipient(address to, address smartWallet) 
        internal 
        view 
        override
        returns (bool) 
    {
        // Allow transfer to smart wallet itself
        if (to == smartWallet) {
            return true;
        }
        
        // Check if `to` is one of the mock Safe wallet's owners
        try mockSafeWallet.getOwners() returns (address[] memory owners) {
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
}

