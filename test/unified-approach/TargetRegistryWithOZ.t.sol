// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { TargetRegistryWithOZ } from "src/unified-approach/TargetRegistryWithOZ.sol";
import { MockSafeWallet } from "test/mocks/MockSafeWallet.sol";
import { TestTargetRegistryWithMockSafe } from "test/mocks/TestTargetRegistryWithMockSafe.sol";

contract TargetRegistryWithOZTest is Test {
    TargetRegistryWithOZ public registry;
    address public owner;
    address public user;
    
    address public mockTarget;
    bytes4 public constant SWAP_SELECTOR = bytes4(keccak256("swap(uint256,uint256)"));

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        mockTarget = makeAddr("mockTarget");
        
        vm.prank(owner);
        registry = new TargetRegistryWithOZ(owner);
    }

    function test_ScheduleAndExecuteAdd() public {
        vm.startPrank(owner);
        
        // Schedule add
        bytes32 opId = registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Check it's pending
        bool isPending = registry.isOperationPending(mockTarget, SWAP_SELECTOR);
        assertTrue(isPending, "Should be pending");
        
        // Check it's not ready yet
        bool isReady = registry.isOperationReady(mockTarget, SWAP_SELECTOR);
        assertFalse(isReady, "Should not be ready yet");
        
        vm.stopPrank();
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days + 1);
        
        // Now it should be ready
        isReady = registry.isOperationReady(mockTarget, SWAP_SELECTOR);
        assertTrue(isReady, "Should be ready now");
        
        // Execute (anyone can execute!)
        vm.prank(user);
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        
        // Verify it's whitelisted
        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted, "Should be whitelisted");
    }
    
    function test_CannotExecuteBeforeTimelock() public {
        vm.prank(owner);
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Try to execute immediately (should fail)
        vm.expectRevert();
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        
        // Try after 23 hours (should still fail)
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert();
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
    }
    
    function test_AnyoneCanExecuteAfterTimelock() public {
        vm.prank(owner);
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Fast forward
        vm.warp(block.timestamp + 1 days + 1);
        
        // Random user can execute
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        
        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted);
    }
    
    function test_CancelOperation() public {
        vm.startPrank(owner);
        
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Cancel it
        registry.cancelOperation(mockTarget, SWAP_SELECTOR);
        
        vm.stopPrank();
        
        // Fast forward
        vm.warp(block.timestamp + 2 days);
        
        // Try to execute (should fail - operation was cancelled)
        vm.expectRevert();
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
    }
    
    function test_GetOperationId() public {
        vm.prank(owner);
        bytes32 scheduledOpId = registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Retrieve using helper
        bytes32 retrievedOpId = registry.getOperationId(mockTarget, SWAP_SELECTOR);
        
        assertEq(scheduledOpId, retrievedOpId, "Operation IDs should match");
    }
    
    /**
     * @notice TEST 6: Registry pause functionality
     */
    function test_RegistryPause() public {
        vm.startPrank(owner);
        
        // Pause the registry
        registry.pause();
        
        // Try to schedule while paused (should fail)
        vm.expectRevert();
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Unpause
        registry.unpause();
        
        // Should work now
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        vm.stopPrank();
    }
    
    /**
     * @notice TEST 7: Only owner can pause registry
     */
    function test_OnlyOwnerCanPauseRegistry() public {
        // Non-owner tries to pause
        vm.prank(user);
        vm.expectRevert();
        registry.pause();
        
        // Owner can pause
        vm.prank(owner);
        registry.pause();
        
        // Non-owner tries to unpause
        vm.prank(user);
        vm.expectRevert();
        registry.unpause();
        
        // Owner can unpause
        vm.prank(owner);
        registry.unpause();
    }
    
    /**
     * @notice TEST 8: ERC20 restriction management
     */
    function test_ERC20RestrictionManagement() public {
        address usdcToken = makeAddr("usdcToken");
        address wethToken = makeAddr("wethToken");
        
        vm.startPrank(owner);
        
        // Test adding restricted token
        assertFalse(registry.restrictedERC20Tokens(usdcToken), "USDC not restricted initially");
        registry.addRestrictedERC20Token(usdcToken);
        assertTrue(registry.restrictedERC20Tokens(usdcToken), "USDC now restricted");
        
        // Test adding same token twice (should fail)
        vm.expectRevert();
        registry.addRestrictedERC20Token(usdcToken);
        
        // Test removing restricted token
        registry.removeRestrictedERC20Token(usdcToken);
        assertFalse(registry.restrictedERC20Tokens(usdcToken), "USDC no longer restricted");
        
        // Test removing non-restricted token (should fail)
        vm.expectRevert();
        registry.removeRestrictedERC20Token(wethToken);
        
        vm.stopPrank();
    }
    
    /**
     * @notice TEST 9: ERC20 transfer authorization with mock Safe wallet
     */
    function test_ERC20TransferAuthorization() public {
        address usdcToken = makeAddr("usdcToken");
        address smartWallet = makeAddr("smartWallet");
        address owner1 = makeAddr("owner1");
        address owner2 = makeAddr("owner2");
        address randomAddress = makeAddr("randomAddress");
        
        // Deploy mock Safe wallet
        address[] memory safeOwners = new address[](2);
        safeOwners[0] = smartWallet; // Smart wallet itself
        safeOwners[1] = owner1; // Additional owner
        
        MockSafeWallet mockSafe = new MockSafeWallet(safeOwners);
        
        // Deploy test registry with mock Safe
        TestTargetRegistryWithMockSafe testRegistry = new TestTargetRegistryWithMockSafe(owner, address(mockSafe));
        
        vm.startPrank(owner);
        
        // Add USDC as restricted token
        testRegistry.addRestrictedERC20Token(usdcToken);
        
        vm.stopPrank();
        
        // Test 1: Non-restricted token should allow all transfers
        address wethToken = makeAddr("wethToken");
        assertTrue(testRegistry.isERC20TransferAuthorized(wethToken, randomAddress, smartWallet), "Non-restricted token allows all transfers");
        
        // Test 2: Restricted token transfer to smart wallet itself should work
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, smartWallet, smartWallet), "Transfer to smart wallet itself allowed");
        
        // Test 3: Restricted token transfer to Safe owner should work
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, owner1, smartWallet), "Transfer to Safe owner allowed");
        
        // Test 4: Restricted token transfer to random address should fail
        assertFalse(testRegistry.isERC20TransferAuthorized(usdcToken, randomAddress, smartWallet), "Transfer to random address blocked");
        
        // Test 5: Test with updated owners
        address[] memory newOwners = new address[](3);
        newOwners[0] = smartWallet;
        newOwners[1] = owner1;
        newOwners[2] = owner2;
        
        mockSafe.setOwners(newOwners);
        
        // Now transfer to owner2 should work
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, owner2, smartWallet), "Transfer to new Safe owner allowed");
    }
}
