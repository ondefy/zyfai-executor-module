// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title ISafeWallet
 * @notice Interface for Safe wallet functions
 */
interface ISafeWallet {
    function getOwners() external view returns (address[] memory);
    function isOwner(address owner) external view returns (bool);
}
