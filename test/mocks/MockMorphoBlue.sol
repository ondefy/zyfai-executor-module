// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title MockMorphoBlue
 * @notice Minimal Morpho Blue mock exposing only setAuthorization, used to test the
 *         GuardedExecModule authorization-grant validation.
 */
contract MockMorphoBlue {
    /// @notice isAuthorized[authorizer][authorized]
    mapping(address => mapping(address => bool)) public isAuthorized;

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
    }
}
