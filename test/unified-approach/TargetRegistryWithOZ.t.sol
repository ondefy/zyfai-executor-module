// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { TargetRegistryWithOZ } from "src/unified-approach/TargetRegistryWithOZ.sol";

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
        
        console.log("Registry deployed:", address(registry));
        console.log("Timelock deployed:", address(registry.timelock()));
        console.log("Owner:", owner);
    }

    function test_ScheduleAndExecuteAdd() public {
        console.log("\n========================================");
        console.log("TEST: Schedule and Execute Add with OZ Timelock");
        console.log("========================================\n");
        
        vm.startPrank(owner);
        
        // Schedule add
        bytes32 opId = registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        console.log("Scheduled operation");
        console.log("Operation ID:", uint256(opId));
        
        // Check it's pending
        bool isPending = registry.isOperationPending(mockTarget, SWAP_SELECTOR);
        assertTrue(isPending, "Should be pending");
        console.log("Operation is pending: true");
        
        // Check it's not ready yet
        bool isReady = registry.isOperationReady(mockTarget, SWAP_SELECTOR);
        assertFalse(isReady, "Should not be ready yet");
        console.log("Operation is ready: false (timelock not expired)");
        
        vm.stopPrank();
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days + 1);
        console.log("\nFast forwarded 1 day");
        
        // Now it should be ready
        isReady = registry.isOperationReady(mockTarget, SWAP_SELECTOR);
        assertTrue(isReady, "Should be ready now");
        console.log("Operation is ready: true");
        
        // Execute (anyone can execute!)
        vm.prank(user);
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        console.log("Executed by user (not owner)");
        
        // Verify it's whitelisted
        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted, "Should be whitelisted");
        console.log("Target+Selector is now whitelisted: true");
        
        console.log("\nSUCCESS: OZ TimelockController works perfectly!");
        console.log("========================================\n");
    }
    
    function test_CannotExecuteBeforeTimelock() public {
        console.log("\n========================================");
        console.log("TEST: Cannot Execute Before Timelock");
        console.log("========================================\n");
        
        vm.prank(owner);
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        console.log("Scheduled operation");
        
        // Try to execute immediately (should fail)
        vm.expectRevert();
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        console.log("Immediate execution blocked: true");
        
        // Try after 23 hours (should still fail)
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert();
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        console.log("Execution before 24h blocked: true");
        
        console.log("\nSUCCESS: Timelock enforced correctly!");
        console.log("========================================\n");
    }
    
    function test_AnyoneCanExecuteAfterTimelock() public {
        console.log("\n========================================");
        console.log("TEST: Anyone Can Execute After Timelock");
        console.log("========================================\n");
        
        vm.prank(owner);
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Fast forward
        vm.warp(block.timestamp + 1 days + 1);
        
        // Random user can execute
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        
        console.log("Random user executed successfully");
        
        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted);
        
        console.log("\nSUCCESS: Permissionless execution works!");
        console.log("========================================\n");
    }
    
    function test_CancelOperation() public {
        console.log("\n========================================");
        console.log("TEST: Cancel Pending Operation");
        console.log("========================================\n");
        
        vm.startPrank(owner);
        
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        console.log("Scheduled operation");
        
        // Cancel it
        registry.cancelOperation(mockTarget, SWAP_SELECTOR);
        console.log("Cancelled operation");
        
        vm.stopPrank();
        
        // Fast forward
        vm.warp(block.timestamp + 2 days);
        
        // Try to execute (should fail - operation was cancelled)
        vm.expectRevert();
        registry.executeOperation(mockTarget, SWAP_SELECTOR);
        
        console.log("\nSUCCESS: Cancelled operation cannot be executed!");
        console.log("========================================\n");
    }
    
    function test_GetOperationId() public {
        console.log("\n========================================");
        console.log("TEST: Get Operation ID Helper");
        console.log("========================================\n");
        
        vm.prank(owner);
        bytes32 scheduledOpId = registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        
        // Retrieve using helper
        bytes32 retrievedOpId = registry.getOperationId(mockTarget, SWAP_SELECTOR);
        
        assertEq(scheduledOpId, retrievedOpId, "Operation IDs should match");
        
        console.log("Scheduled opId:", uint256(scheduledOpId));
        console.log("Retrieved opId:", uint256(retrievedOpId));
        console.log("Match: true");
        
        console.log("\nSUCCESS: Easy opId retrieval works!");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 6: Registry pause functionality
     */
    function test_RegistryPause() public {
        console.log("\n========================================");
        console.log("TEST 6: Registry Pause/Unpause");
        console.log("========================================\n");
        
        vm.startPrank(owner);
        
        // Pause the registry
        registry.pause();
        console.log("Registry paused");
        
        // Try to schedule while paused (should fail)
        vm.expectRevert();
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        console.log("Scheduling blocked while paused");
        
        // Unpause
        registry.unpause();
        console.log("Registry unpaused");
        
        // Should work now
        registry.scheduleAdd(mockTarget, SWAP_SELECTOR);
        console.log("Scheduling works after unpause");
        
        vm.stopPrank();
        
        console.log("\nSUCCESS: Pause/unpause works correctly!");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 7: Only owner can pause registry
     */
    function test_OnlyOwnerCanPauseRegistry() public {
        console.log("\n========================================");
        console.log("TEST 7: Registry Pause Access Control");
        console.log("========================================\n");
        
        // Non-owner tries to pause
        vm.prank(user);
        vm.expectRevert();
        registry.pause();
        console.log("Non-owner cannot pause");
        
        // Owner can pause
        vm.prank(owner);
        registry.pause();
        console.log("Owner can pause");
        
        // Non-owner tries to unpause
        vm.prank(user);
        vm.expectRevert();
        registry.unpause();
        console.log("Non-owner cannot unpause");
        
        // Owner can unpause
        vm.prank(owner);
        registry.unpause();
        console.log("Owner can unpause");
        
        console.log("\nSUCCESS: Only owner can pause/unpause registry!");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 8: ERC20 restriction management
     */
    function test_ERC20RestrictionManagement() public {
        console.log("\n========================================");
        console.log("TEST 8: ERC20 Restriction Management");
        console.log("========================================\n");
        
        address usdcToken = makeAddr("usdcToken");
        address wethToken = makeAddr("wethToken");
        
        vm.startPrank(owner);
        
        // Test adding restricted token
        assertFalse(registry.restrictedERC20Tokens(usdcToken), "USDC not restricted initially");
        registry.addRestrictedERC20Token(usdcToken);
        assertTrue(registry.restrictedERC20Tokens(usdcToken), "USDC now restricted");
        console.log("SUCCESS: Added USDC as restricted token");
        
        // Test adding same token twice (should fail)
        vm.expectRevert();
        registry.addRestrictedERC20Token(usdcToken);
        console.log("BLOCKED: Cannot add already restricted token (as expected)");
        
        // Test removing restricted token
        registry.removeRestrictedERC20Token(usdcToken);
        assertFalse(registry.restrictedERC20Tokens(usdcToken), "USDC no longer restricted");
        console.log("SUCCESS: Removed USDC from restricted tokens");
        
        // Test removing non-restricted token (should fail)
        vm.expectRevert();
        registry.removeRestrictedERC20Token(wethToken);
        console.log("BLOCKED: Cannot remove non-restricted token (as expected)");
        
        vm.stopPrank();
        
        console.log("\nSUCCESS: ERC20 restriction management working correctly!");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 9: ERC20 transfer authorization with mock Safe wallet
     */
    function test_ERC20TransferAuthorization() public {
        console.log("\n========================================");
        console.log("TEST 9: ERC20 Transfer Authorization with Mock Safe");
        console.log("========================================\n");
        
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
        console.log("Mock Safe deployed:", address(mockSafe));
        console.log("Safe owners:", safeOwners[0], safeOwners[1]);
        
        // Deploy test registry with mock Safe
        TestTargetRegistryWithMockSafe testRegistry = new TestTargetRegistryWithMockSafe(owner, address(mockSafe));
        
        vm.startPrank(owner);
        
        // Add USDC as restricted token
        testRegistry.addRestrictedERC20Token(usdcToken);
        console.log("Added USDC as restricted token");
        
        vm.stopPrank();
        
        // Test 1: Non-restricted token should allow all transfers
        address wethToken = makeAddr("wethToken");
        assertTrue(testRegistry.isERC20TransferAuthorized(wethToken, randomAddress, smartWallet), "Non-restricted token allows all transfers");
        console.log("SUCCESS: Non-restricted token allows all transfers");
        
        // Test 2: Restricted token transfer to smart wallet itself should work
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, smartWallet, smartWallet), "Transfer to smart wallet itself allowed");
        console.log("SUCCESS: Transfer to smart wallet itself ALLOWED");
        
        // Test 3: Restricted token transfer to Safe owner should work
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, owner1, smartWallet), "Transfer to Safe owner allowed");
        console.log("SUCCESS: Transfer to Safe owner ALLOWED");
        
        // Test 4: Restricted token transfer to random address should fail
        assertFalse(testRegistry.isERC20TransferAuthorized(usdcToken, randomAddress, smartWallet), "Transfer to random address blocked");
        console.log("BLOCKED: Transfer to random address");
        
        // Test 5: Test with updated owners
        address[] memory newOwners = new address[](3);
        newOwners[0] = smartWallet;
        newOwners[1] = owner1;
        newOwners[2] = owner2;
        
        mockSafe.setOwners(newOwners);
        console.log("Updated Safe owners to include owner2");
        
        // Now transfer to owner2 should work
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, owner2, smartWallet), "Transfer to new Safe owner allowed");
        console.log("SUCCESS: Transfer to new Safe owner ALLOWED");
        
        console.log("\nSUCCESS: ERC20 transfer authorization with mock Safe working correctly!");
        console.log("========================================\n");
    }
}

/**
 * @title MockSafeWallet
 * @notice Mock Safe wallet that implements getOwners() and setOwners() functions
 */
contract MockSafeWallet {
    address[] public owners;
    
    constructor(address[] memory _owners) {
        owners = _owners;
    }
    
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    function setOwners(address[] memory _owners) external {
        owners = _owners;
    }
    
    function addOwner(address newOwner) external {
        owners.push(newOwner);
    }
    
    function removeOwner(address ownerToRemove) external {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
    }
    
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }
    
    function isOwner(address account) external view returns (bool) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == account) {
                return true;
            }
        }
        return false;
    }
}

/**
 * @title TestTargetRegistryWithMockSafe
 * @notice Test registry that uses mock Safe wallet for getOwners() calls
 */
contract TestTargetRegistryWithMockSafe is TargetRegistryWithOZ {
    MockSafeWallet public mockSafeWallet;
    
    constructor(address admin, address _mockSafeWallet) TargetRegistryWithOZ(admin) {
        mockSafeWallet = MockSafeWallet(_mockSafeWallet);
    }
    
    function _isAuthorizedRecipient(address to, address smartWallet) 
        internal 
        view 
        override
        returns (bool) 
    {
        // Allow transfer to smart wallet itself
        if (to == smartWallet) {
            return true;
        }
        
        // Check if `to` is one of the mock Safe wallet's owners
        try mockSafeWallet.getOwners() returns (address[] memory owners) {
            for (uint256 i = 0; i < owners.length; i++) {
                if (owners[i] == to) {
                    return true;
                }
            }
        } catch {
            // If getOwners() fails, only allow transfer to smart wallet itself
            return false;
        }
        
        return false;
    }
}

