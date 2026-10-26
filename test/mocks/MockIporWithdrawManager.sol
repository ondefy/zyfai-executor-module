// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IIporWithdrawManager } from "src/interfaces/IIporWithdrawManager.sol";

/**
 * @title MockPlasmaVaultShares
 * @notice Vault share token whose WithdrawManager can move any holder's shares, like IPOR
 *         `PlasmaVaultBase.transferRequestSharesFee` (no allowance needed)
 */
contract MockPlasmaVaultShares is ERC20 {
    address public immutable withdrawManager;

    error Unauthorized();

    constructor() ERC20("Mock Plasma Vault", "mPV") {
        withdrawManager = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferRequestSharesFee(address from_, address to_, uint256 amount_) external {
        if (msg.sender != withdrawManager) revert Unauthorized();
        _transfer(from_, to_, amount_);
    }
}

/**
 * @title MockIporWithdrawManager
 * @notice Reproduces IPOR Fusion `WithdrawManager.requestShares` fee logic: the fee is taken
 *         from the caller's vault shares, `shares_` is not capped by the caller's balance, and
 *         each request overwrites the previous one with a fresh withdraw window. Used to test
 *         the GuardedExecModule request checks.
 */
contract MockIporWithdrawManager {
    struct WithdrawRequest {
        uint256 shares;
        uint256 endWithdrawWindowTimestamp;
    }

    MockPlasmaVaultShares public immutable plasmaVault;
    uint256 public getRequestFee;
    uint256 public getWithdrawWindow = 1 days;
    mapping(address => WithdrawRequest) internal requests;

    error WithdrawManagerZeroShares();

    constructor() {
        plasmaVault = new MockPlasmaVaultShares();
    }

    /// @notice Test helper: IPOR restricts this to WITHDRAW_MANAGER_REQUEST_FEE_ROLE
    function updateRequestFee(uint256 fee_) external {
        getRequestFee = fee_;
    }

    /// @notice Test helper: IPOR restricts this to ATOMIST_ROLE
    function updateWithdrawWindow(uint256 window_) external {
        getWithdrawWindow = window_;
    }

    function getPlasmaVaultAddress() external view returns (address) {
        return address(plasmaVault);
    }

    function requestedShares(address account_) external view returns (uint256) {
        return requests[account_].shares;
    }

    function requestInfo(address account_)
        external
        view
        returns (IIporWithdrawManager.WithdrawRequestInfo memory)
    {
        WithdrawRequest memory request = requests[account_];
        return IIporWithdrawManager.WithdrawRequestInfo({
            shares: request.shares,
            endWithdrawWindowTimestamp: request.endWithdrawWindowTimestamp,
            canWithdraw: false,
            withdrawWindowInSeconds: getWithdrawWindow
        });
    }

    function requestShares(uint256 shares_) external {
        if (shares_ == 0) revert WithdrawManagerZeroShares();

        uint256 feeRate = getRequestFee;
        if (feeRate > 0) {
            uint256 feeAmount = Math.mulDiv(shares_, feeRate, 1e18);
            _updateRequest(msg.sender, shares_ - feeAmount);
            plasmaVault.transferRequestSharesFee(msg.sender, address(this), feeAmount);
        } else {
            _updateRequest(msg.sender, shares_);
        }
    }

    /// @notice Test helper: IPOR decreases the request when the vault redeems from it
    function clearRequest(address account_) external {
        requests[account_].shares = 0;
    }

    function _updateRequest(address account_, uint256 shares_) internal {
        requests[account_] = WithdrawRequest({
            shares: shares_, endWithdrawWindowTimestamp: block.timestamp + getWithdrawWindow
        });
    }
}
