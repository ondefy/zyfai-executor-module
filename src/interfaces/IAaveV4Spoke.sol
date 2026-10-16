// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IAaveV4Spoke
 * @notice Minimal Aave v4 risk Spoke interface used by GuardedExecModule to read a smart
 *         account's health factor (aave/aave-v4 `ISpoke`)
 */
interface IAaveV4Spoke {
    /**
     * @notice User account data describing a position and its health (`ISpoke.UserAccountData`)
     * @dev healthFactor is in WAD (1e18 = 1.00) and is type(uint256).max when the user has no
     *      debt. Field order must match `ISpoke.UserAccountData` for ABI decoding.
     */
    struct UserAccountData {
        uint256 riskPremium;
        uint256 avgCollateralFactor;
        uint256 healthFactor;
        uint256 totalCollateralValue;
        uint256 totalDebtValueRay;
        uint256 activeCollateralCount;
        uint256 borrowCount;
    }

    function getUserAccountData(address user) external view returns (UserAccountData memory);
}
