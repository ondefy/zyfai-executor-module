// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title MockSafeWallet
 * @author ZyFAI
 * @notice Mock Safe wallet contract for testing purposes - NOT for production use
 * @dev Implements getOwners() function to simulate Safe wallet interface for ERC20 transfer authorization tests
 */
contract MockSafeWallet {
    /**
     * @notice Array of owner addresses
     */
    address[] public owners;
    
    /**
     * @notice Constructor for mock Safe wallet
     * @param _owners Array of initial owner addresses
     */
    constructor(address[] memory _owners) {
        owners = _owners;
    }
    
    /**
     * @notice Get all owner addresses
     * @dev Simulates Safe wallet's getOwners() function used by TargetRegistry
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    /**
     * @notice Set owner addresses (for testing)
     * @dev Permissionless function for test purposes only
     * @param _owners New array of owner addresses
     */
    function setOwners(address[] memory _owners) external {
        owners = _owners;
    }
    
    /**
     * @notice Add a new owner (for testing)
     * @dev Permissionless function for test purposes only
     * @param newOwner Address of the new owner to add
     */
    function addOwner(address newOwner) external {
        owners.push(newOwner);
    }
    
    /**
     * @notice Remove an owner (for testing)
     * @dev Permissionless function for test purposes only. Uses swap-and-pop pattern for gas efficiency.
     * @param ownerToRemove Address of the owner to remove
     */
    function removeOwner(address ownerToRemove) external {
        uint256 length = owners.length;
        for (uint256 i = 0; i < length;) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[length - 1];
                owners.pop();
                break;
            }
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Get the number of owners
     * @return Number of owners
     */
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }
    
    /**
     * @notice Check if an address is an owner
     * @param account Address to check
     * @return True if the address is an owner
     */
    function isOwner(address account) external view returns (bool) {
        uint256 length = owners.length;
        for (uint256 i = 0; i < length;) {
            if (owners[i] == account) {
                return true;
            }
            unchecked { ++i; }
        }
        return false;
    }
}

