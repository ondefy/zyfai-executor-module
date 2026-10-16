// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IAaveV4Spoke } from "src/interfaces/IAaveV4Spoke.sol";

/**
 * @title MockAaveV4Spoke
 * @notice Minimal Aave v4 risk Spoke mock with one reserve and a collateral factor of 1, so
 *         healthFactor = collateral * 1e18 / debt (type(uint256).max without debt). Like the real
 *         Spoke it binds onBehalfOf to the caller. It does not enforce the Spoke's own
 *         healthFactor >= 1e18 rule, so tests can reach any health factor.
 *         Used to test the GuardedExecModule minimum health factor check.
 */
contract MockAaveV4Spoke {
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    mapping(address => bool) public usingAsCollateral;

    error Unauthorized();

    modifier onlyPositionManager(address onBehalfOf) {
        if (msg.sender != onBehalfOf) revert Unauthorized();
        _;
    }

    /// @notice Test helper: set a position directly
    function setPosition(address user, uint256 collateral_, uint256 debt_, bool enabled) external {
        collateral[user] = collateral_;
        debt[user] = debt_;
        usingAsCollateral[user] = enabled;
    }

    function supply(
        uint256,
        uint256 amount,
        address onBehalfOf
    )
        external
        onlyPositionManager(onBehalfOf)
        returns (uint256, uint256)
    {
        collateral[onBehalfOf] += amount;
        return (amount, amount);
    }

    function withdraw(
        uint256,
        uint256 amount,
        address onBehalfOf
    )
        external
        onlyPositionManager(onBehalfOf)
        returns (uint256, uint256)
    {
        if (amount > collateral[onBehalfOf]) amount = collateral[onBehalfOf];
        collateral[onBehalfOf] -= amount;
        return (amount, amount);
    }

    function borrow(
        uint256,
        uint256 amount,
        address onBehalfOf
    )
        external
        onlyPositionManager(onBehalfOf)
        returns (uint256, uint256)
    {
        debt[onBehalfOf] += amount;
        return (amount, amount);
    }

    function repay(
        uint256,
        uint256 amount,
        address onBehalfOf
    )
        external
        onlyPositionManager(onBehalfOf)
        returns (uint256, uint256)
    {
        if (amount > debt[onBehalfOf]) amount = debt[onBehalfOf];
        debt[onBehalfOf] -= amount;
        return (amount, amount);
    }

    function setUsingAsCollateral(
        uint256,
        bool enabled,
        address onBehalfOf
    )
        external
        onlyPositionManager(onBehalfOf)
    {
        usingAsCollateral[onBehalfOf] = enabled;
    }

    function getUserAccountData(address user)
        external
        view
        returns (IAaveV4Spoke.UserAccountData memory data)
    {
        data.healthFactor = _healthFactor(user);
        data.borrowCount = debt[user] > 0 ? 1 : 0;
    }

    function _healthFactor(address user) internal view returns (uint256) {
        if (debt[user] == 0) return type(uint256).max;
        if (!usingAsCollateral[user]) return 0;
        return collateral[user] * 1e18 / debt[user];
    }
}
