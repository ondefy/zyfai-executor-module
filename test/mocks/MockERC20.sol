// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @author ZyFAI
 * @notice Mock ERC20 token contract for testing purposes - NOT for production use
 * @dev Extends OpenZeppelin ERC20 with mint functionality and custom decimals for testing
 */
contract MockERC20 is ERC20 {
    /**
     * @notice Decimals for this token (configurable in constructor)
     */
    uint8 private _decimals;

    /**
     * @notice Constructor for mock ERC20 token
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Number of decimals (e.g., 18 for ETH, 6 for USDC)
     */
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /**
     * @notice Returns the number of decimals for the token
     * @return Number of decimals
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to an address (for testing only)
     * @dev Permissionless minting - only for test purposes
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
