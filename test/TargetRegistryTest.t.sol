// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { TargetRegistry } from "src/registry/TargetRegistry.sol";
import { MockSafeWallet } from "test/mocks/MockSafeWallet.sol";
import { TestTargetRegistryWithMockSafe } from "test/mocks/TestTargetRegistryWithMockSafe.sol";

contract TargetRegistryTest is Test {
    TargetRegistry public registry;
    address public owner;
    address public user;
    
    address public mockTarget;
    bytes4 public constant SWAP_SELECTOR = bytes4(keccak256("swap(uint256,uint256)"));

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        mockTarget = makeAddr("mockTarget");
        
        vm.prank(owner);
        registry = new TargetRegistry(owner);
    }

    function test_ScheduleAndExecuteAdd() public {
        vm.startPrank(owner);
        
        // Schedule add
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        bytes32[] memory opIds = registry.scheduleAdd(targets, selectors);
        
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
        registry.executeOperation(targets, selectors);
        
        // Verify it's whitelisted
        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted, "Should be whitelisted");
    }
    
    function test_CannotExecuteBeforeTimelock() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.prank(owner);
        registry.scheduleAdd(targets, selectors);
        
        // Try to execute immediately (should fail)
        vm.expectRevert();
        registry.executeOperation(targets, selectors);
        
        // Try after 23 hours (should still fail)
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert();
        registry.executeOperation(targets, selectors);
    }
    
    function test_AnyoneCanExecuteAfterTimelock() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.prank(owner);
        registry.scheduleAdd(targets, selectors);
        
        // Fast forward
        vm.warp(block.timestamp + 1 days + 1);
        
        // Random user can execute
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        registry.executeOperation(targets, selectors);
        
        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted);
    }
    
    function test_CancelOperation() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.startPrank(owner);
        
        registry.scheduleAdd(targets, selectors);
        
        // Cancel it
        registry.cancelOperation(targets, selectors);
        
        vm.stopPrank();
        
        // Fast forward
        vm.warp(block.timestamp + 2 days);
        
        // Try to execute (should fail - operation was cancelled)
        vm.expectRevert();
        registry.executeOperation(targets, selectors);
    }
    
    function test_GetOperationId() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.prank(owner);
        bytes32[] memory scheduledOpIds = registry.scheduleAdd(targets, selectors);
        
        // Retrieve using helper
        bytes32 retrievedOpId = registry.getOperationId(mockTarget, SWAP_SELECTOR);
        
        assertEq(scheduledOpIds[0], retrievedOpId, "Operation IDs should match");
    }
    
    /**
     * @notice TEST 6: Registry pause functionality
     */
    function test_RegistryPause() public {
        vm.startPrank(owner);
        
        // Pause the registry
        registry.pause();
        
        // Try to schedule while paused (should fail)
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        vm.expectRevert();
        registry.scheduleAdd(targets, selectors);
        
        // Unpause
        registry.unpause();
        
        // Should work now
        registry.scheduleAdd(targets, selectors);
        
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
        assertFalse(registry.allowedERC20Tokens(usdcToken), "USDC not allowed initially");
        address[] memory tokens = new address[](1);
        tokens[0] = usdcToken;
        registry.addAllowedERC20Token(tokens);
        assertTrue(registry.allowedERC20Tokens(usdcToken), "USDC now allowed");
        
        // Test adding same token twice (should fail)
        vm.expectRevert();
        registry.addAllowedERC20Token(tokens);
        
        // Test removing restricted token
        registry.removeAllowedERC20Token(tokens);
        assertFalse(registry.allowedERC20Tokens(usdcToken), "USDC no longer allowed");
        
        // Test removing non-restricted token (should fail)
        address[] memory wethArray = new address[](1);
        wethArray[0] = wethToken;
        vm.expectRevert();
        registry.removeAllowedERC20Token(wethArray);
        
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
        address[] memory usdcArray1 = new address[](1);
        usdcArray1[0] = usdcToken;
        testRegistry.addAllowedERC20Token(usdcArray1);
        
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
    
    /**
     * @notice Test transfers to allowed recipients
     */
    function test_ERC20TransferToAllowedRecipient() public {
        address usdcToken = makeAddr("usdcToken");
        address feeVault = makeAddr("feeVault");
        address smartWallet = makeAddr("smartWallet");
        
        // Deploy mock Safe wallet
        address[] memory safeOwners = new address[](1);
        safeOwners[0] = smartWallet;
        
        MockSafeWallet mockSafe = new MockSafeWallet(safeOwners);
        
        // Deploy test registry with mock Safe
        TestTargetRegistryWithMockSafe testRegistry = new TestTargetRegistryWithMockSafe(owner, address(mockSafe));
        
        vm.startPrank(owner);
        
        // Add USDC as restricted token
        address[] memory usdcArray2 = new address[](1);
        usdcArray2[0] = usdcToken;
        testRegistry.addAllowedERC20Token(usdcArray2);
        
        // Add fee vault as allowed recipient
        address[] memory feeVaultArray1 = new address[](1);
        feeVaultArray1[0] = feeVault;
        testRegistry.addAllowedERC20TokenRecipient(usdcToken, feeVaultArray1);
        
        // Verify transfer to fee vault is authorized
        assertTrue(testRegistry.isERC20TransferAuthorized(usdcToken, feeVault, smartWallet), "Transfer to fee vault should be authorized");
        
        // Verify transfer to random address is NOT authorized
        address randomAddress = makeAddr("randomAddress");
        assertFalse(testRegistry.isERC20TransferAuthorized(usdcToken, randomAddress, smartWallet), "Transfer to random address should not be authorized");
        
        // Remove fee vault from allowed recipients
        testRegistry.removeAllowedERC20TokenRecipient(usdcToken, feeVaultArray1);
        
        // Verify transfer to fee vault is now NOT authorized
        assertFalse(testRegistry.isERC20TransferAuthorized(usdcToken, feeVault, smartWallet), "Transfer to fee vault should not be authorized after removal");
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test adding and removing allowed ERC20 token recipients
     */
    function test_AllowedERC20TokenRecipientManagement() public {
        address usdcToken = makeAddr("usdcToken");
        address feeVault = makeAddr("feeVault");
        address morphoAdapter = makeAddr("morphoAdapter");
        
        vm.startPrank(owner);
        
        // Add USDC as allowed token
        address[] memory usdcArray = new address[](1);
        usdcArray[0] = usdcToken;
        registry.addAllowedERC20Token(usdcArray);
        
        // Test adding fee vault as allowed recipient
        assertFalse(registry.allowedERC20TokenRecipients(usdcToken, feeVault), "Fee vault not allowed initially");
        address[] memory feeVaultArray = new address[](1);
        feeVaultArray[0] = feeVault;
        registry.addAllowedERC20TokenRecipient(usdcToken, feeVaultArray);
        assertTrue(registry.allowedERC20TokenRecipients(usdcToken, feeVault), "Fee vault now allowed");
        
        // Test adding morpho adapter as allowed recipient
        address[] memory morphoArray = new address[](1);
        morphoArray[0] = morphoAdapter;
        registry.addAllowedERC20TokenRecipient(usdcToken, morphoArray);
        assertTrue(registry.allowedERC20TokenRecipients(usdcToken, morphoAdapter), "Morpho adapter now allowed");
        
        // Test removing fee vault
        registry.removeAllowedERC20TokenRecipient(usdcToken, feeVaultArray);
        assertFalse(registry.allowedERC20TokenRecipients(usdcToken, feeVault), "Fee vault no longer allowed");
        
        // Test adding same recipient twice (should fail)
        vm.expectRevert();
        registry.addAllowedERC20TokenRecipient(usdcToken, morphoArray); // Already allowed
        
        // Test removing non-allowed recipient (should fail)
        vm.expectRevert();
        registry.removeAllowedERC20TokenRecipient(usdcToken, feeVaultArray); // Not allowed
        
        // Test adding recipient for token not in allowedERC20Tokens (should fail)
        registry.removeAllowedERC20Token(usdcArray);
        vm.expectRevert();
        registry.addAllowedERC20TokenRecipient(usdcToken, feeVaultArray); // USDC not in allowedERC20Tokens
        
        vm.stopPrank();
    }
}
