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

    /**
     * @notice Test: Add target+selector to whitelist directly
     */
    function test_AddToWhitelist() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);
        
        // Verify it's whitelisted (using auto-generated getter)
        bool whitelisted = registry.whitelist(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted, "Should be whitelisted");

        // Verify target is marked as whitelisted (using auto-generated getter)
        assertTrue(registry.whitelistedTargets(mockTarget), "Target should be marked as whitelisted");
        assertEq(registry.whitelistedSelectorCount(mockTarget), 1, "Selector count should be 1");
    }
    
    /**
     * @notice Test: Remove target+selector from whitelist directly
     */
    function test_RemoveFromWhitelist() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        // First add it
        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);
        assertTrue(registry.whitelist(mockTarget, SWAP_SELECTOR), "Should be whitelisted");

        // Then remove it
        vm.prank(owner);
        registry.removeFromWhitelist(targets, selectors);
        
        // Verify it's not whitelisted (using auto-generated getter)
        bool whitelisted = registry.whitelist(mockTarget, SWAP_SELECTOR);
        assertFalse(whitelisted, "Should not be whitelisted");

        // Verify target is no longer marked as whitelisted (using auto-generated getter)
        assertFalse(registry.whitelistedTargets(mockTarget), "Target should not be marked as whitelisted");
        assertEq(registry.whitelistedSelectorCount(mockTarget), 0, "Selector count should be 0");
    }

    /**
     * @notice Test: Only owner can add to whitelist
     */
    function test_OnlyOwnerCanAddToWhitelist() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        // Non-owner cannot add
        vm.prank(user);
        vm.expectRevert();
        registry.addToWhitelist(targets, selectors);
        
        // Owner can add
        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);
        assertTrue(registry.whitelist(mockTarget, SWAP_SELECTOR), "Should be whitelisted");
    }
    
    /**
     * @notice Test: Only owner can remove from whitelist
     */
    function test_OnlyOwnerCanRemoveFromWhitelist() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        // First add it (as owner)
        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);
        
        // Non-owner cannot remove
        vm.prank(user);
        vm.expectRevert();
        registry.removeFromWhitelist(targets, selectors);
        
        // Owner can remove
        vm.prank(owner);
        registry.removeFromWhitelist(targets, selectors);
        assertFalse(registry.whitelist(mockTarget, SWAP_SELECTOR), "Should not be whitelisted");
    }
    
    /**
     * @notice Test: Cannot add already whitelisted target+selector
     */
    function test_CannotAddAlreadyWhitelisted() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.startPrank(owner);
        registry.addToWhitelist(targets, selectors);
        
        // Try to add again (should fail)
        vm.expectRevert(TargetRegistry.AlreadyWhitelisted.selector);
        registry.addToWhitelist(targets, selectors);
        vm.stopPrank();
    }

    /**
     * @notice Test: Cannot remove non-whitelisted target+selector
     */
    function test_CannotRemoveNotWhitelisted() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.prank(owner);
        vm.expectRevert(TargetRegistry.NotWhitelisted.selector);
        registry.removeFromWhitelist(targets, selectors);
    }
    
    /**
     * @notice Test: Registry pause prevents whitelist operations
     */
    function test_RegistryPause() public {
        vm.startPrank(owner);
        
        // Pause the registry
        registry.pause();
        
        // Try to add while paused (should fail)
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        vm.expectRevert();
        registry.addToWhitelist(targets, selectors);

        // Try to remove while paused (should fail)
        vm.expectRevert();
        registry.removeFromWhitelist(targets, selectors);

        // Try to add ERC20 recipient while paused (should fail)
        address token = makeAddr("token");
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient");
        vm.expectRevert();
        registry.addAllowedERC20TokenRecipient(token, recipients);

        // Try to remove ERC20 recipient while paused (should fail)
        vm.expectRevert();
        registry.removeAllowedERC20TokenRecipient(token, recipients);
        
        // Unpause
        registry.unpause();
        
        // Should work now
        registry.addToWhitelist(targets, selectors);
        assertTrue(registry.whitelist(mockTarget, SWAP_SELECTOR), "Should be whitelisted");
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test: Only owner can pause and unpause registry
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
     * @notice Test: ERC20 transfer authorization checks with mock Safe wallet
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
        TestTargetRegistryWithMockSafe testRegistry =
            new TestTargetRegistryWithMockSafe(owner, address(mockSafe));
        
        // All tokens are now effectively restricted by default
        // Test 1: Any token transfer to random address should fail
        address wethToken = makeAddr("wethToken");
        assertFalse(
            testRegistry.isERC20TransferAuthorized(wethToken, randomAddress, smartWallet), 
            "Non-authorized recipient blocked"
        );
        
        // Test 2: Transfer to smart wallet itself should work
        assertTrue(
            testRegistry.isERC20TransferAuthorized(usdcToken, smartWallet, smartWallet), 
            "Transfer to smart wallet itself allowed"
        );
        
        // Test 3: Transfer to Safe owner should work
        assertTrue(
            testRegistry.isERC20TransferAuthorized(usdcToken, owner1, smartWallet), 
            "Transfer to Safe owner allowed"
        );
        
        // Test 4: Transfer to random address should fail
        assertFalse(
            testRegistry.isERC20TransferAuthorized(usdcToken, randomAddress, smartWallet), 
            "Transfer to random address blocked"
        );
        
        // Test 5: Test with updated owners
        address[] memory newOwners = new address[](3);
        newOwners[0] = smartWallet;
        newOwners[1] = owner1;
        newOwners[2] = owner2;
        
        mockSafe.setOwners(newOwners);
        
        // Now transfer to owner2 should work
        assertTrue(
            testRegistry.isERC20TransferAuthorized(usdcToken, owner2, smartWallet), 
            "Transfer to new Safe owner allowed"
        );
    }
    
    /**
     * @notice Test: ERC20 transfers to explicitly allowed recipients
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
        TestTargetRegistryWithMockSafe testRegistry =
            new TestTargetRegistryWithMockSafe(owner, address(mockSafe));
        
        vm.startPrank(owner);
        
        // Add fee vault as allowed recipient
        address[] memory feeVaultArray1 = new address[](1);
        feeVaultArray1[0] = feeVault;
        testRegistry.addAllowedERC20TokenRecipient(usdcToken, feeVaultArray1);
        
        // Verify transfer to fee vault is authorized
        assertTrue(
            testRegistry.isERC20TransferAuthorized(usdcToken, feeVault, smartWallet), 
            "Transfer to fee vault should be authorized"
        );
        
        // Verify transfer to random address is NOT authorized
        address randomAddress = makeAddr("randomAddress");
        assertFalse(
            testRegistry.isERC20TransferAuthorized(usdcToken, randomAddress, smartWallet), 
            "Transfer to random address should not be authorized"
        );
        
        // Remove fee vault from allowed recipients
        testRegistry.removeAllowedERC20TokenRecipient(usdcToken, feeVaultArray1);
        
        // Verify transfer to fee vault is now NOT authorized
        assertFalse(
            testRegistry.isERC20TransferAuthorized(usdcToken, feeVault, smartWallet), 
            "Transfer to fee vault should not be authorized after removal"
        );
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test: Add and remove allowed ERC20 token recipients
     */
    function test_AllowedERC20TokenRecipientManagement() public {
        address usdcToken = makeAddr("usdcToken");
        address feeVault = makeAddr("feeVault");
        address morphoAdapter = makeAddr("morphoAdapter");
        
        vm.startPrank(owner);
        
        // Test adding fee vault as allowed recipient
        assertFalse(
            registry.allowedERC20TokenRecipients(usdcToken, feeVault),
            "Fee vault not allowed initially"
        );
        address[] memory feeVaultArray = new address[](1);
        feeVaultArray[0] = feeVault;
        registry.addAllowedERC20TokenRecipient(usdcToken, feeVaultArray);
        assertTrue(
            registry.allowedERC20TokenRecipients(usdcToken, feeVault), "Fee vault now allowed"
        );
        
        // Test adding morpho adapter as allowed recipient
        address[] memory morphoArray = new address[](1);
        morphoArray[0] = morphoAdapter;
        registry.addAllowedERC20TokenRecipient(usdcToken, morphoArray);
        assertTrue(
            registry.allowedERC20TokenRecipients(usdcToken, morphoAdapter),
            "Morpho adapter now allowed"
        );
        
        // Test removing fee vault
        registry.removeAllowedERC20TokenRecipient(usdcToken, feeVaultArray);
        assertFalse(
            registry.allowedERC20TokenRecipients(usdcToken, feeVault), "Fee vault no longer allowed"
        );
        
        // Test adding same recipient twice (should fail)
        vm.expectRevert();
        registry.addAllowedERC20TokenRecipient(usdcToken, morphoArray); // Already allowed
        
        // Test removing non-allowed recipient (should fail)
        vm.expectRevert();
        registry.removeAllowedERC20TokenRecipient(usdcToken, feeVaultArray); // Not allowed
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test: Can add and remove multiple times
     */
    function test_CanAddAndRemoveMultipleTimes() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.startPrank(owner);

        // Add
        registry.addToWhitelist(targets, selectors);
        assertTrue(
            registry.whitelist(mockTarget, SWAP_SELECTOR), "Should be whitelisted after add"
        );

        // Remove
        registry.removeFromWhitelist(targets, selectors);
        assertFalse(
            registry.whitelist(mockTarget, SWAP_SELECTOR),
            "Should not be whitelisted after remove"
        );

        // Add again
        registry.addToWhitelist(targets, selectors);
        assertTrue(
            registry.whitelist(mockTarget, SWAP_SELECTOR),
            "Should be whitelisted after second add"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test: Batch operations work correctly
     */
    function test_BatchOperations() public {
        address target1 = makeAddr("target1");
        address target2 = makeAddr("target2");
        bytes4 selector1 = SWAP_SELECTOR;
        bytes4 selector2 = bytes4(keccak256("deposit(uint256)"));

        address[] memory targets = new address[](2);
        targets[0] = target1;
        targets[1] = target2;
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = selector1;
        selectors[1] = selector2;

        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);

        assertTrue(registry.whitelist(target1, selector1), "Target1+selector1 should be whitelisted");
        assertTrue(registry.whitelist(target2, selector2), "Target2+selector2 should be whitelisted");
        assertEq(registry.whitelistedSelectorCount(target1), 1, "Target1 should have 1 selector");
        assertEq(registry.whitelistedSelectorCount(target2), 1, "Target2 should have 1 selector");

        vm.prank(owner);
        registry.removeFromWhitelist(targets, selectors);

        assertFalse(registry.whitelist(target1, selector1), "Target1+selector1 should not be whitelisted");
        assertFalse(registry.whitelist(target2, selector2), "Target2+selector2 should not be whitelisted");
    }

    /**
     * @notice Test: Cannot add with empty batch
     */
    function test_CannotAddEmptyBatch() public {
        address[] memory emptyTargets = new address[](0);
        bytes4[] memory emptySelectors = new bytes4[](0);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.EmptyBatch.selector);
        registry.addToWhitelist(emptyTargets, emptySelectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.EmptyBatch.selector);
        registry.removeFromWhitelist(emptyTargets, emptySelectors);
    }

    /**
     * @notice Test: Cannot add with mismatched array lengths
     */
    function test_CannotAddWithLengthMismatch() public {
        address[] memory targets = new address[](2);
        targets[0] = mockTarget;
        targets[1] = makeAddr("target2");
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.LengthMismatch.selector);
        registry.addToWhitelist(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.LengthMismatch.selector);
        registry.removeFromWhitelist(targets, selectors);
    }
    
    /**
     * @notice Test: Cannot add with zero address target
     */
    function test_CannotAddZeroAddressTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        
        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidTarget.selector);
        registry.addToWhitelist(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidTarget.selector);
        registry.removeFromWhitelist(targets, selectors);
    }

    /**
     * @notice Test: Cannot add with zero selector
     */
    function test_CannotAddZeroSelector() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(0);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidSelector.selector);
        registry.addToWhitelist(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidSelector.selector);
        registry.removeFromWhitelist(targets, selectors);
    }

    /**
     * @notice Test: Cannot add ERC20 recipient with zero token address
     */
    function test_CannotAddERC20RecipientWithZeroToken() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient");

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidERC20Token.selector);
        registry.addAllowedERC20TokenRecipient(address(0), recipients);
    }

    /**
     * @notice Test: Cannot add ERC20 recipient with zero recipient address
     */
    function test_CannotAddERC20RecipientWithZeroRecipient() public {
        address token = makeAddr("token");
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidRecipient.selector);
        registry.addAllowedERC20TokenRecipient(token, recipients);
    }

    /**
     * @notice Test: Multiple selectors on same target update counter correctly
     */
    function test_MultipleSelectorsOnSameTarget() public {
        bytes4 selector1 = SWAP_SELECTOR;
        bytes4 selector2 = bytes4(keccak256("deposit(uint256)"));
        bytes4 selector3 = bytes4(keccak256("withdraw(uint256)"));

        vm.startPrank(owner);

        // Add first selector
        address[] memory targets1 = new address[](1);
        targets1[0] = mockTarget;
        bytes4[] memory selectors1 = new bytes4[](1);
        selectors1[0] = selector1;
        registry.addToWhitelist(targets1, selectors1);

        assertEq(registry.whitelistedSelectorCount(mockTarget), 1, "Should have 1 selector");
        assertTrue(registry.whitelistedTargets(mockTarget), "Target should be whitelisted");

        // Add second selector
        bytes4[] memory selectors2 = new bytes4[](1);
        selectors2[0] = selector2;
        registry.addToWhitelist(targets1, selectors2);

        assertEq(registry.whitelistedSelectorCount(mockTarget), 2, "Should have 2 selectors");
        assertTrue(registry.whitelistedTargets(mockTarget), "Target should still be whitelisted");

        // Remove first selector
        registry.removeFromWhitelist(targets1, selectors1);

        assertEq(registry.whitelistedSelectorCount(mockTarget), 1, "Should have 1 selector");
        assertTrue(registry.whitelistedTargets(mockTarget), "Target should still be whitelisted");

        // Remove second selector
        registry.removeFromWhitelist(targets1, selectors2);

        assertEq(registry.whitelistedSelectorCount(mockTarget), 0, "Should have 0 selectors");
        assertFalse(registry.whitelistedTargets(mockTarget), "Target should no longer be whitelisted");

        vm.stopPrank();
    }

    /**
     * @notice Test: Two-step ownership transfer works correctly
     * @dev Verifies that ownership transfer requires two steps: transferOwnership() then acceptOwnership()
     *      This prevents accidental or malicious immediate ownership transfers.
     */
    function test_TwoStepOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        // Step 1: Current owner initiates transfer
        vm.prank(owner);
        registry.transferOwnership(newOwner);

        // Verify pending owner is set
        assertEq(registry.pendingOwner(), newOwner, "Pending owner should be set");

        // Verify current owner hasn't changed yet
        assertEq(registry.owner(), owner, "Current owner should not have changed yet");

        // Non-pending owner cannot accept
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        registry.acceptOwnership();

        // Step 2: New owner accepts ownership
        vm.prank(newOwner);
        registry.acceptOwnership();

        // Verify ownership has transferred
        assertEq(registry.owner(), newOwner, "New owner should be set");
        assertEq(registry.pendingOwner(), address(0), "Pending owner should be cleared");
        assertNotEq(registry.owner(), owner, "Old owner should no longer be owner");

        // New owner can now perform owner functions
        vm.prank(newOwner);
        registry.pause();
        assertTrue(registry.paused(), "New owner should be able to pause");

        vm.prank(newOwner);
        registry.unpause();
        assertFalse(registry.paused(), "New owner should be able to unpause");
    }

    /**
     * @notice Test: Owner can replace pending owner
     * @dev Verifies that owner can change the pending owner before acceptance.
     */
    function test_OwnerCanReplacePendingOwner() public {
        address firstPendingOwner = makeAddr("firstPendingOwner");
        address secondPendingOwner = makeAddr("secondPendingOwner");

        // Owner sets first pending owner
        vm.prank(owner);
        registry.transferOwnership(firstPendingOwner);
        assertEq(registry.pendingOwner(), firstPendingOwner, "First pending owner should be set");
        
        // Owner replaces with second pending owner
        vm.prank(owner);
        registry.transferOwnership(secondPendingOwner);
        assertEq(registry.pendingOwner(), secondPendingOwner, "Second pending owner should be set");

        // First pending owner cannot accept (replaced)
        vm.prank(firstPendingOwner);
        vm.expectRevert();
        registry.acceptOwnership();

        // Second pending owner can accept
        vm.prank(secondPendingOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), secondPendingOwner, "Second pending owner should become owner");
    }
}
