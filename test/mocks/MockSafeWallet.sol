// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title MockSafeWallet
 * @notice Mock Safe wallet that implements getOwners() and setOwners() functions
 */
contract MockSafeWallet {
    address[] public owners;
    
    constructor(address[] memory _owners) {
        owners = _owners;
    }
    
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    function setOwners(address[] memory _owners) external {
        owners = _owners;
    }
    
    function addOwner(address newOwner) external {
        owners.push(newOwner);
    }
    
    function removeOwner(address ownerToRemove) external {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
    }
    
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }
    
    function isOwner(address account) external view returns (bool) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == account) {
                return true;
            }
        }
        return false;
    }
}

