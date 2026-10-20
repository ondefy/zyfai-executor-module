// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IIporWithdrawManager
 * @notice Minimal IPOR Fusion WithdrawManager interface used by GuardedExecModule to bound
 *         scheduled-withdrawal requests (ipor-fusion `WithdrawManager`)
 */
interface IIporWithdrawManager {
    struct WithdrawRequestInfo {
        uint256 shares;
        uint256 endWithdrawWindowTimestamp;
        bool canWithdraw;
        uint256 withdrawWindowInSeconds;
    }

    /// @notice Fee charged in vault shares on `requestShares`, in WAD (1e18 = 100%)
    function getRequestFee() external view returns (uint256);

    /// @notice PlasmaVault whose shares the request fee is taken from
    function getPlasmaVaultAddress() external view returns (address);

    /// @notice Current withdrawal request of `account_`
    function requestInfo(address account_) external view returns (WithdrawRequestInfo memory);
}
