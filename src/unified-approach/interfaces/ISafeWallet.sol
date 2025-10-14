// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title ISafeWallet
 * @notice Interface for Safe wallet's getOwners() function
 */
interface ISafeWallet {
    function getOwners() external view returns (address[] memory);
}