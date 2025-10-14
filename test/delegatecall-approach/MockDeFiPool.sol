// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/console.sol";

/**
 * @title MockDeFiPool
 * @notice Mock DeFi protocol (like Uniswap, Aave, etc.) to test msg.sender behavior
 * @dev This contract logs who called it to verify the smart account is the caller
 */
contract MockDeFiPool {
    
    event Swap(address indexed caller, uint256 amountIn, uint256 amountOut);
    event Deposit(address indexed caller, uint256 amount);
    event Withdraw(address indexed caller, uint256 amount);
    
    // Store the last caller to verify in tests
    address public lastCaller;
    uint256 public callCount;
    
    /**
     * @notice Mock swap function
     * @dev Records msg.sender to verify it's the smart account
     */
    function swap(uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        console.log("\n*** MockDeFiPool.swap() called ***");
        console.log("msg.sender (should be smart account):", msg.sender);
        console.log("amountIn:", amountIn);
        console.log("minAmountOut:", minAmountOut);
        
        lastCaller = msg.sender;
        callCount++;
        
        // Mock swap logic - just return 90% of input as output
        amountOut = (amountIn * 90) / 100;
        
        console.log("amountOut:", amountOut);
        console.log("*** MockDeFiPool.swap() completed ***\n");
        
        emit Swap(msg.sender, amountIn, amountOut);
        return amountOut;
    }
    
    /**
     * @notice Mock deposit function
     */
    function deposit(uint256 amount) external {
        console.log("\n*** MockDeFiPool.deposit() called ***");
        console.log("msg.sender (should be smart account):", msg.sender);
        console.log("amount:", amount);
        
        lastCaller = msg.sender;
        callCount++;
        
        console.log("*** MockDeFiPool.deposit() completed ***\n");
        
        emit Deposit(msg.sender, amount);
    }
    
    /**
     * @notice Mock withdraw function
     */
    function withdraw(uint256 amount) external returns (bool) {
        console.log("\n*** MockDeFiPool.withdraw() called ***");
        console.log("msg.sender (should be smart account):", msg.sender);
        console.log("amount:", amount);
        
        lastCaller = msg.sender;
        callCount++;
        
        console.log("*** MockDeFiPool.withdraw() completed ***\n");
        
        emit Withdraw(msg.sender, amount);
        return true;
    }
    
    /**
     * @notice Function that reverts to test error handling
     */
    function failingFunction() external pure {
        console.log("\n*** MockDeFiPool.failingFunction() called ***");
        console.log("This will revert!");
        revert("Intentional failure");
    }
    
    /**
     * @notice Get information about the last call
     */
    function getLastCallInfo() external view returns (address caller, uint256 count) {
        return (lastCaller, callCount);
    }
}

