// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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
 *         each request overwrites the previous one. Used to test the GuardedExecModule
 *         request fee check.
 */
contract MockIporWithdrawManager {
    MockPlasmaVaultShares public immutable plasmaVault;
    uint256 public getRequestFee;
    mapping(address => uint256) public requestedShares;

    error WithdrawManagerZeroShares();

    constructor() {
        plasmaVault = new MockPlasmaVaultShares();
    }

    /// @notice Test helper: IPOR restricts this to WITHDRAW_MANAGER_REQUEST_FEE_ROLE
    function updateRequestFee(uint256 fee_) external {
        getRequestFee = fee_;
    }

    function requestShares(uint256 shares_) external {
        if (shares_ == 0) revert WithdrawManagerZeroShares();

        uint256 feeRate = getRequestFee;
        if (feeRate > 0) {
            uint256 feeAmount = Math.mulDiv(shares_, feeRate, 1e18);
            requestedShares[msg.sender] = shares_ - feeAmount;
            plasmaVault.transferRequestSharesFee(msg.sender, address(this), feeAmount);
        } else {
            requestedShares[msg.sender] = shares_;
        }
    }
}
