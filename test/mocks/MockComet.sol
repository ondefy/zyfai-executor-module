// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title MockComet
 * @notice Minimal Compound V3 Comet mock reproducing the behaviour the GuardedExecModule guards
 *         against: `withdraw` of the base asset past the supplied balance becomes a borrow
 *         against the account's collateral. `supply` credits the base balance (repaying debt
 *         first) for the base asset and collateral for anything else, as the real Comet does.
 *         Collateral is valued 1:1 instead of Comet's per-asset collateral factors, and no tokens
 *         move. Used to test the GuardedExecModule no-Comet-debt check.
 */
contract MockComet {
    address public immutable baseToken;

    mapping(address => uint256) public baseBalance;
    mapping(address => uint256) public debt;
    mapping(address => uint256) public collateral;

    error NotCollateralized();

    constructor(address baseToken_) {
        baseToken = baseToken_;
    }

    /// @notice Test helper: set an account's base balance, debt and collateral directly
    function setPosition(
        address account,
        uint256 base,
        uint256 owed,
        uint256 collateralAmount
    )
        external
    {
        baseBalance[account] = base;
        debt[account] = owed;
        collateral[account] = collateralAmount;
    }

    function supply(address asset, uint256 amount) external {
        if (asset != baseToken) {
            collateral[msg.sender] += amount;
            return;
        }

        uint256 owed = debt[msg.sender];
        uint256 repaid = amount < owed ? amount : owed;
        debt[msg.sender] = owed - repaid;
        baseBalance[msg.sender] += amount - repaid;
    }

    function withdraw(address asset, uint256 amount) external {
        if (asset != baseToken) {
            collateral[msg.sender] -= amount;
            if (debt[msg.sender] > collateral[msg.sender]) revert NotCollateralized();
            return;
        }

        uint256 supplied = baseBalance[msg.sender];
        uint256 fromSupply = amount < supplied ? amount : supplied;
        baseBalance[msg.sender] = supplied - fromSupply;

        uint256 borrowed = amount - fromSupply;
        if (borrowed == 0) return;

        debt[msg.sender] += borrowed;
        if (debt[msg.sender] > collateral[msg.sender]) revert NotCollateralized();
    }

    function borrowBalanceOf(address account) external view returns (uint256) {
        return debt[account];
    }
}
