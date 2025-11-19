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
     * @notice Test: Schedule and execute whitelist addition after timelock delay
     */
    function test_ScheduleAndExecuteAdd() public {
        vm.startPrank(owner);

        // Schedule add
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;
        registry.scheduleAdd(targets, selectors);

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

    /**
     * @notice Test: Cannot execute scheduled operation before timelock expires
     */
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

        // Try after 30 seconds (should still fail)
        vm.warp(block.timestamp + 30 seconds);
        vm.expectRevert();
        registry.executeOperation(targets, selectors);
    }

    /**
     * @notice Test: Anyone can execute scheduled operation after timelock expires
     */
    function test_AnyoneCanExecuteAfterTimelock() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        vm.prank(owner);
        registry.scheduleAdd(targets, selectors);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days + 1);

        // Random user can execute
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        registry.executeOperation(targets, selectors);

        bool whitelisted = registry.isWhitelisted(mockTarget, SWAP_SELECTOR);
        assertTrue(whitelisted);
    }

    /**
     * @notice Test: Owner can cancel pending operation before execution
     */
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

    /**
     * @notice Test: Get operation ID for scheduled operation
     */
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
     * @notice Test: Registry pause prevents scheduling operations
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
     * @notice Test: Execute operation is blocked when registry is paused
     * @dev Verifies that executeOperation() respects the pause state and reverts when paused.
     *      This prevents scheduled operations from executing during emergency situations.
     */
    function test_ExecuteOperationBlockedWhenPaused() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        // Schedule an operation
        vm.prank(owner);
        registry.scheduleAdd(targets, selectors);

        // Fast forward past timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Verify operation is ready to execute
        assertTrue(registry.isOperationReady(mockTarget, SWAP_SELECTOR), "Operation should be ready");

        // Pause the registry (emergency stop)
        vm.prank(owner);
        registry.pause();

        // Try to execute while paused (should fail)
        vm.expectRevert();
        registry.executeOperation(targets, selectors);

        // Unpause
        vm.prank(owner);
        registry.unpause();

        // Now execution should work
        registry.executeOperation(targets, selectors);

        // Verify it was executed
        assertTrue(registry.isWhitelisted(mockTarget, SWAP_SELECTOR), "Should be whitelisted after execution");
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
     * @notice Test: Can re-schedule same target+selector after execution
     * @dev Verifies that unique salt allows re-scheduling the same pair
     */
    function test_CanRescheduleAfterExecution() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        // ✅ CRITICAL TEST: Can add → execute → remove → execute → add again
        // This would have FAILED with the old fixed salt implementation

        // Step 1: Add
        vm.prank(owner);
        registry.scheduleAdd(targets, selectors);
        vm.warp(block.timestamp + 1 days + 1);
        registry.executeOperation(targets, selectors);
        assertTrue(
            registry.isWhitelisted(mockTarget, SWAP_SELECTOR), "Should be whitelisted after add"
        );

        // Step 2: Remove
        vm.prank(owner);
        registry.scheduleRemove(targets, selectors);
        vm.warp(block.timestamp + 1 days + 1);
        registry.executeOperation(targets, selectors);
        assertFalse(
            registry.isWhitelisted(mockTarget, SWAP_SELECTOR),
            "Should not be whitelisted after remove"
        );

        // Step 3: Add again (this would have FAILED before the fix!)
        vm.prank(owner);
        registry.scheduleAdd(targets, selectors); // ✅ Should work now with unique salt!
        vm.warp(block.timestamp + 1 days + 1);
        registry.executeOperation(targets, selectors);
        assertTrue(
            registry.isWhitelisted(mockTarget, SWAP_SELECTOR),
            "Should be whitelisted after second add"
        );
    }

    /**
     * @notice Test: Cannot schedule duplicate operation before execution
     */
    function test_CannotScheduleDuplicateOperation() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        // Schedule first operation
        vm.prank(owner);
        registry.scheduleAdd(targets, selectors);

        // Try to schedule again before executing the first (should fail)
        vm.prank(owner);
        vm.expectRevert(TargetRegistry.PendingOperationExists.selector);
        registry.scheduleAdd(targets, selectors);
    }

    /**
     * @notice Test: Cannot schedule with empty batch
     */
    function test_CannotScheduleEmptyBatch() public {
        address[] memory emptyTargets = new address[](0);
        bytes4[] memory emptySelectors = new bytes4[](0);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.EmptyBatch.selector);
        registry.scheduleAdd(emptyTargets, emptySelectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.EmptyBatch.selector);
        registry.scheduleRemove(emptyTargets, emptySelectors);
    }

    /**
     * @notice Test: Cannot schedule with mismatched array lengths
     */
    function test_CannotScheduleWithLengthMismatch() public {
        address[] memory targets = new address[](2);
        targets[0] = mockTarget;
        targets[1] = makeAddr("target2");
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.LengthMismatch.selector);
        registry.scheduleAdd(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.LengthMismatch.selector);
        registry.scheduleRemove(targets, selectors);
    }

    /**
     * @notice Test: Cannot schedule with zero address target
     */
    function test_CannotScheduleZeroAddressTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidTarget.selector);
        registry.scheduleAdd(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidTarget.selector);
        registry.scheduleRemove(targets, selectors);
    }

    /**
     * @notice Test: Cannot schedule with zero selector
     */
    function test_CannotScheduleZeroSelector() public {
        address[] memory targets = new address[](1);
        targets[0] = mockTarget;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(0);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidSelector.selector);
        registry.scheduleAdd(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.InvalidSelector.selector);
        registry.scheduleRemove(targets, selectors);
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
     * @notice Test: Cannot execute with empty batch
     */
    function test_CannotExecuteEmptyBatch() public {
        address[] memory emptyTargets = new address[](0);
        bytes4[] memory emptySelectors = new bytes4[](0);

        vm.expectRevert(TargetRegistry.EmptyBatch.selector);
        registry.executeOperation(emptyTargets, emptySelectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.EmptyBatch.selector);
        registry.cancelOperation(emptyTargets, emptySelectors);
    }

    /**
     * @notice Test: Cannot execute with mismatched array lengths
     */
    function test_CannotExecuteWithLengthMismatch() public {
        address[] memory targets = new address[](2);
        targets[0] = mockTarget;
        targets[1] = makeAddr("target2");
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SWAP_SELECTOR;

        vm.expectRevert(TargetRegistry.LengthMismatch.selector);
        registry.executeOperation(targets, selectors);

        vm.prank(owner);
        vm.expectRevert(TargetRegistry.LengthMismatch.selector);
        registry.cancelOperation(targets, selectors);
    }

    /**
     * @notice Test: Nonce ensures unique operation IDs (prevents salt collision vulnerability)
     * @dev Demonstrates that scheduling multiple operations produces different operation IDs
     *      even when scheduled in the same block/timestamp, due to the nonce counter.
     *      Without nonce, if block.timestamp and block.prevrandao were identical,
     *      salts could collide. Nonce prevents this attack.
     */
    function test_NonceEnsuresUniqueOperationIds() public {
        address target1 = makeAddr("target1");
        address target2 = makeAddr("target2");
        address target3 = makeAddr("target3");
        address target4 = makeAddr("target4");
        bytes4 selector = SWAP_SELECTOR;

        address[] memory targets1 = new address[](1);
        targets1[0] = target1;
        address[] memory targets2 = new address[](1);
        targets2[0] = target2;
        address[] memory targets3 = new address[](1);
        targets3[0] = target3;
        address[] memory targets4 = new address[](1);
        targets4[0] = target4;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        // Schedule four operations in rapid succession (same timestamp)
        // Without nonce, if timestamp+prevrandao matched, salts could collide
        vm.startPrank(owner);
        bytes32 opId1 = registry.scheduleAdd(targets1, selectors)[0];
        bytes32 opId2 = registry.scheduleAdd(targets2, selectors)[0];
        bytes32 opId3 = registry.scheduleAdd(targets3, selectors)[0];
        bytes32 opId4 = registry.scheduleAdd(targets4, selectors)[0];
        vm.stopPrank();

        // All operation IDs must be unique (nonce increments ensure this)
        assertNotEq(opId1, opId2, "Operation IDs 1 and 2 must be unique");
        assertNotEq(opId1, opId3, "Operation IDs 1 and 3 must be unique");
        assertNotEq(opId1, opId4, "Operation IDs 1 and 4 must be unique");
        assertNotEq(opId2, opId3, "Operation IDs 2 and 3 must be unique");
        assertNotEq(opId2, opId4, "Operation IDs 2 and 4 must be unique");
        assertNotEq(opId3, opId4, "Operation IDs 3 and 4 must be unique");

        // Now test add/remove cycle to verify nonce continues to ensure uniqueness
        vm.warp(block.timestamp + 1 days + 1);
        registry.executeOperation(targets1, selectors);

        // Remove target1
        vm.prank(owner);
        bytes32 removeOpId = registry.scheduleRemove(targets1, selectors)[0];

        // Remove operation ID must be different from add operation ID
        assertNotEq(opId1, removeOpId, "Add and remove operations must have unique IDs");

        // Execute removal
        vm.warp(block.timestamp + 1 days + 1);
        registry.executeOperation(targets1, selectors);

        // Add target1 again - should get different operation ID due to nonce
        vm.prank(owner);
        bytes32 secondAddOpId = registry.scheduleAdd(targets1, selectors)[0];

        // All operation IDs must be different (nonce increments on each operation)
        assertNotEq(opId1, secondAddOpId, "First and second add must have unique IDs");
        assertNotEq(removeOpId, secondAddOpId, "Remove and second add must have unique IDs");
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
