// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IComet
 * @notice Minimal Compound V3 interface used by GuardedExecModule to read a smart account's
 *         base-asset debt on a Comet market (compound-finance/comet `Comet`)
 */
interface IComet {
    /**
     * @notice The account's base-asset debt, in base-token decimals
     * @dev Zero while the account is a net supplier of the base asset. A Comet account is either
     *      a supplier or a borrower, never both, so this single read separates lending from
     *      borrowing.
     */
    function borrowBalanceOf(address account) external view returns (uint256);
}
