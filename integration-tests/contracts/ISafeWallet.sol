// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title ISafeWallet
 * @notice Interface for Safe wallet functionality needed by TargetRegistry
 * @dev This interface matches the Safe wallet's getOwners() method
 */
interface ISafeWallet {
    /**
     * @notice Returns the list of owners
     * @return owners Array of owner addresses
     */
    function getOwners() external view returns (address[] memory owners);
}
