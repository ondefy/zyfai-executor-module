// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title MockOperatorVault
 * @notice Minimal ERC-7540 vault mock exposing only setOperator (as on Superform SuperVaults),
 *         used to test the GuardedExecModule authorization-grant validation.
 */
contract MockOperatorVault {
    /// @notice isOperator[controller][operator]
    mapping(address => mapping(address => bool)) public isOperator;

    function setOperator(address operator, bool approved) external returns (bool) {
        isOperator[msg.sender][operator] = approved;
        return true;
    }
}
