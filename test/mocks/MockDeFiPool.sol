// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title MockDeFiPool
 * @author ZyFAI
 * @notice Mock DeFi protocol contract for testing purposes - NOT for production use
 * @dev Simulates DeFi protocols (like Uniswap, Aave, Curve) to test msg.sender behavior.
 *      Records caller addresses to verify smart account context is maintained.
 */
contract MockDeFiPool {
    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when swap function is called
     * @param caller The address that called the function
     * @param amountIn The amount swapped in
     * @param amountOut The amount swapped out
     */
    event Swap(address indexed caller, uint256 amountIn, uint256 amountOut);

    /**
     * @notice Emitted when deposit function is called
     * @param caller The address that called the function
     * @param amount The amount deposited
     */
    event Deposit(address indexed caller, uint256 amount);

    /**
     * @notice Emitted when withdraw function is called
     * @param caller The address that called the function
     * @param amount The amount withdrawn
     */
    event Withdraw(address indexed caller, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The address that last called a function on this contract
     * @dev Used to verify msg.sender is the smart account (not the module or session key)
     */
    address public lastCaller;

    /**
     * @notice Total number of function calls made to this contract
     * @dev Used to verify functions were called the expected number of times
     */
    uint256 public callCount;

    /**
     * @notice Mock swap function
     * @dev Records msg.sender to verify it's the smart account.
     *      Second parameter is unused but kept for interface compatibility.
     * @param amountIn The amount to swap in
     * @return amountOut The amount swapped out
     */
    function swap(uint256 amountIn, uint256) external returns (uint256 amountOut) {
        lastCaller = msg.sender;
        callCount++;

        // Mock swap logic - just return 90% of input as output
        amountOut = (amountIn * 90) / 100;

        emit Swap(msg.sender, amountIn, amountOut);
        return amountOut;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mock deposit function
     * @dev Records msg.sender to verify smart account context
     * @param amount The amount to deposit
     */
    function deposit(uint256 amount) external {
        lastCaller = msg.sender;
        callCount++;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Mock withdraw function
     * @dev Records msg.sender to verify smart account context
     * @param amount The amount to withdraw
     * @return True on success
     */
    function withdraw(uint256 amount) external returns (bool) {
        lastCaller = msg.sender;
        callCount++;
        emit Withdraw(msg.sender, amount);
        return true;
    }

    /**
     * @notice Function that always reverts (for testing error handling)
     * @dev Used to test error propagation in batch operations
     */
    function failingFunction() external pure {
        revert("Intentional failure");
    }

    /**
     * @notice Get information about the last function call
     * @dev Returns the last caller and total call count for test verification
     * @return caller The address that made the last call
     * @return count Total number of calls made to this contract
     */
    function getLastCallInfo() external view returns (address caller, uint256 count) {
        return (lastCaller, callCount);
    }
}
