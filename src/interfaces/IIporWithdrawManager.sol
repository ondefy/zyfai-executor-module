// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IIporWithdrawManager
 * @notice Minimal IPOR Fusion WithdrawManager interface used by GuardedExecModule to read the
 *         scheduled-withdrawal request fee (ipor-fusion `WithdrawManager`)
 */
interface IIporWithdrawManager {
    /// @notice Fee charged in vault shares on `requestShares`, in WAD (1e18 = 100%)
    function getRequestFee() external view returns (uint256);
}
