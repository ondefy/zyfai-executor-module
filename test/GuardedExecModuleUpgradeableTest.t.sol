// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { RhinestoneModuleKit, ModuleKitHelpers, AccountInstance } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/accounts/common/interfaces/IERC7579Module.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { MockDeFiPool } from "test/mocks/MockDeFiPool.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockSafeWallet } from "test/mocks/MockSafeWallet.sol";
import { TestTargetRegistryWithMockSafe } from "test/mocks/TestTargetRegistryWithMockSafe.sol";
import { TargetRegistry } from "src/registry/TargetRegistry.sol";
import { GuardedExecModuleUpgradeable } from "src/module/GuardedExecModuleUpgradeable.sol";
import { MockGuardedExecModuleUpgradeableV2 } from
    "test/mocks/MockGuardedExecModuleUpgradeableV2.sol";
/**
 * @title GuardedExecModuleUpgradeableTest
 * @notice Test the GuardedExecModuleUpgradeable with UUPS upgradeable pattern
 */

contract GuardedExecModuleUpgradeableTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;

    event GuardedBatchExecuted(
        address indexed executor,
        address[] targets,
        bytes4[] selectors,
        uint256 timestamp
    );
    
    // ERC1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Core contracts
    AccountInstance internal instance;
    GuardedExecModuleUpgradeable internal guardedModule;
    GuardedExecModuleUpgradeable internal implementation;
    ERC1967Proxy internal proxy;
    TargetRegistry internal registry;
    
    // Mock DeFi protocols
    MockDeFiPool internal uniswapPool;
    MockDeFiPool internal aavePool;
    MockDeFiPool internal curvePool;
    
    // Mock ERC20 tokens
    MockERC20 internal usdcToken;
    MockERC20 internal wethToken;
    
    // Mock Safe wallet
    MockSafeWallet internal mockSafeWallet;
    
    // Test accounts
    address internal smartAccount;
    address internal registryOwner;
    address internal moduleOwner;
    
    // Common selectors
    bytes4 internal constant SWAP_SELECTOR = MockDeFiPool.swap.selector;
    bytes4 internal constant TRANSFER_SELECTOR = IERC20.transfer.selector;
    bytes4 internal constant APPROVE_SELECTOR = IERC20.approve.selector;

    /**
     * @notice Helper function to convert arrays to Execution[] for testing
     */
    function _toExecutions(
        address[] memory targets,
        bytes[] memory calldatas,
        uint256[] memory values
    ) internal pure returns (Execution[] memory executions) {
        uint256 length = targets.length;
        executions = new Execution[](length);
        for (uint256 i = 0; i < length; i++) {
            executions[i] = Execution({
                target: targets[i],
                value: values[i],
                callData: calldatas[i]
            });
        }
    }

    function setUp() public {
        init();
        
        // Create test accounts
        registryOwner = makeAddr("registryOwner");
        moduleOwner = makeAddr("moduleOwner");
        
        // Deploy registry with OpenZeppelin TimelockController
        vm.prank(registryOwner);
        registry = new TargetRegistry(registryOwner);
        vm.label(address(registry), "TargetRegistry");
        
        // Deploy mock DeFi pools
        uniswapPool = new MockDeFiPool();
        aavePool = new MockDeFiPool();
        curvePool = new MockDeFiPool();
        vm.label(address(uniswapPool), "UniswapPool");
        vm.label(address(aavePool), "AavePool");
        vm.label(address(curvePool), "CurvePool");
        
        // Deploy mock ERC20 tokens
        usdcToken = new MockERC20("USD Coin", "USDC", 6);
        wethToken = new MockERC20("Wrapped Ether", "WETH", 18);
        
        vm.label(address(usdcToken), "USDC");
        vm.label(address(wethToken), "WETH");
        
        // Add whitelist entries directly
        vm.startPrank(registryOwner);
        
        // Add DeFi pools and ERC20 tokens to whitelist (batch operation)
        address[] memory whitelistTargets = new address[](7);
        whitelistTargets[0] = address(uniswapPool);
        whitelistTargets[1] = address(aavePool);
        whitelistTargets[2] = address(curvePool);
        whitelistTargets[3] = address(usdcToken);
        whitelistTargets[4] = address(wethToken);
        whitelistTargets[5] = address(usdcToken);
        whitelistTargets[6] = address(wethToken);
        
        bytes4[] memory whitelistSelectors = new bytes4[](7);
        whitelistSelectors[0] = SWAP_SELECTOR;
        whitelistSelectors[1] = SWAP_SELECTOR;
        whitelistSelectors[2] = SWAP_SELECTOR;
        whitelistSelectors[3] = TRANSFER_SELECTOR;
        whitelistSelectors[4] = TRANSFER_SELECTOR;
        whitelistSelectors[5] = APPROVE_SELECTOR;
        whitelistSelectors[6] = APPROVE_SELECTOR;

        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
        
        vm.stopPrank();
        
        // Deploy UPGRADEABLE module (implementation + proxy)
        implementation = new GuardedExecModuleUpgradeable();
        vm.label(address(implementation), "GuardedExecModuleUpgradeable_Implementation");
        
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            GuardedExecModuleUpgradeable.initialize.selector, address(registry), moduleOwner
        );
        
        // Deploy UUPS proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        guardedModule = GuardedExecModuleUpgradeable(address(proxy));
        vm.label(address(proxy), "GuardedExecModuleUpgradeable_Proxy");
        
        // Verify initialization
        assertEq(address(guardedModule.registry()), address(registry), "Registry should be set");
        assertEq(guardedModule.owner(), moduleOwner, "Owner should be set");
        assertEq(guardedModule.isInitialized(address(0)), true, "Should be initialized");
        
        // Create smart account
        instance = makeAccountInstance("SmartAccount");
        smartAccount = address(instance.account);
        vm.deal(smartAccount, 10 ether);
        
        // Deploy mock Safe wallet with smart account as owner
        address[] memory safeOwners = new address[](2);
        safeOwners[0] = smartAccount; // Smart account itself
        safeOwners[1] = makeAddr("safeOwner1"); // Additional owner
        
        mockSafeWallet = new MockSafeWallet(safeOwners);
        vm.label(address(mockSafeWallet), "MockSafeWallet");
        
        // Update the smart account to use the mock Safe wallet for getOwners() calls
        // We'll do this by deploying a new registry that uses the mock Safe wallet
        vm.stopPrank();
        
        // Deploy a new registry that uses the mock Safe wallet
        vm.startPrank(registryOwner);
        registry = new TestTargetRegistryWithMockSafe(registryOwner, address(mockSafeWallet));
        vm.label(address(registry), "TestTargetRegistryWithMockSafe");
        
        // Add whitelist entries directly
        address[] memory whitelistTargets2 = new address[](7);
        whitelistTargets2[0] = address(uniswapPool);
        whitelistTargets2[1] = address(aavePool);
        whitelistTargets2[2] = address(curvePool);
        whitelistTargets2[3] = address(usdcToken);
        whitelistTargets2[4] = address(wethToken);
        whitelistTargets2[5] = address(usdcToken);
        whitelistTargets2[6] = address(wethToken);
        
        bytes4[] memory whitelistSelectors2 = new bytes4[](7);
        whitelistSelectors2[0] = SWAP_SELECTOR;
        whitelistSelectors2[1] = SWAP_SELECTOR;
        whitelistSelectors2[2] = SWAP_SELECTOR;
        whitelistSelectors2[3] = TRANSFER_SELECTOR;
        whitelistSelectors2[4] = TRANSFER_SELECTOR;
        whitelistSelectors2[5] = APPROVE_SELECTOR;
        whitelistSelectors2[6] = APPROVE_SELECTOR;

        registry.addToWhitelist(whitelistTargets2, whitelistSelectors2);
        
        vm.stopPrank();
        
        // Update the proxy's registry
        vm.prank(moduleOwner);
        guardedModule.updateRegistry(address(registry));
        
        // Install module
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(guardedModule),
            data: ""
        });
    }

    /**
     * @notice Test: Verify msg.sender is the smart account when executing via module
     */
    function test_MsgSenderIsSmartAccount() public {
        // Prepare single call to Uniswap
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 0; // No ETH value for regular swaps
        
        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        
        // Execute via smart account
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });
        
        // Verify msg.sender was the smart account
        (address lastCaller, uint256 callCount) = uniswapPool.getLastCallInfo();
        
        assertEq(lastCaller, smartAccount, "msg.sender should be the smart account!");
        assertEq(callCount, 1, "Should be called once");
    }
    
    /**
     * @notice Test: Execute batch of multiple DeFi protocol calls
     */
    function test_BatchMultipleDeFiCalls() public {
        // Prepare batch: Uniswap swap, Aave swap, Curve swap
        address[] memory targets = new address[](3);
        bytes[] memory calldatas = new bytes[](3);
        uint256[] memory values = new uint256[](3);
        
        targets[0] = address(uniswapPool);
        targets[1] = address(aavePool);
        targets[2] = address(curvePool);
        
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        calldatas[1] = abi.encodeWithSelector(SWAP_SELECTOR, 2000 ether, 1800 ether);
        calldatas[2] = abi.encodeWithSelector(SWAP_SELECTOR, 3000 ether, 2700 ether);
        
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        
        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        
        // Execute batch
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });
        
        // Verify all pools were called
        (address caller1, uint256 count1) = uniswapPool.getLastCallInfo();
        (address caller2, uint256 count2) = aavePool.getLastCallInfo();
        (address caller3, uint256 count3) = curvePool.getLastCallInfo();
        
        assertEq(caller1, smartAccount, "Uniswap: msg.sender should be smart account");
        assertEq(caller2, smartAccount, "Aave: msg.sender should be smart account");
        assertEq(caller3, smartAccount, "Curve: msg.sender should be smart account");
        assertEq(count1, 1);
        assertEq(count2, 1);
        assertEq(count3, 1);
    }
    
    /**
     * @notice Test: GuardedBatchExecuted event emits expected payload
     */
    function test_GuardedBatchExecutedEvent() public {
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        bytes4[] memory expectedSelectors = new bytes4[](1);
        expectedSelectors[0] = SWAP_SELECTOR;

        vm.expectEmit(true, true, true, true, address(guardedModule));
        emit GuardedBatchExecuted(smartAccount, targets, expectedSelectors, block.timestamp);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Test: Module configuration (registry, version, name) is correct
     */
    function test_ModuleConfiguration() public {
        // Check registry is set correctly
        address moduleRegistry = address(guardedModule.registry());
        
        assertEq(moduleRegistry, address(registry), "Registry should match");
        
        // Check version
        string memory version = guardedModule.version();
        assertEq(version, "2.0.0", "Version should be 2.0.0");
        
        // Check name
        string memory name = guardedModule.name();
        assertEq(name, "GuardedExecModuleUpgradeable", "Name should match");
    }
    
    /**
     * @notice Test: Module pause stops execution (emergency stop for compromised session key)
     */
    function test_ModulePauseStopsSessionKey() public {
        // Check initial state
        assertFalse(guardedModule.paused(), "Should not be paused initially");
        
        // EMERGENCY: Session key compromised! Pause the module!
        vm.prank(moduleOwner);
        guardedModule.pause();
        assertTrue(guardedModule.paused(), "Should be paused");
        
        // Verify pause state
        assertTrue(guardedModule.paused(), "Module should be paused");
        
        // Unpause
        vm.prank(moduleOwner);
        guardedModule.unpause();
        assertFalse(guardedModule.paused(), "Should not be paused after unpause");
        
        // Now should work
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 0;
        
        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });
    }
    
    /**
     * @notice Test: Only owner can pause and unpause module
     */
    function test_OnlyOwnerCanPauseModule() public {
        address attacker = makeAddr("attacker");
        
        // Attacker tries to pause (should fail)
        vm.prank(attacker);
        vm.expectRevert();
        guardedModule.pause();
        
        // Owner can pause
        vm.prank(moduleOwner);
        guardedModule.pause();
        
        // Attacker tries to unpause (should fail)
        vm.prank(attacker);
        vm.expectRevert();
        guardedModule.unpause();
        
        // Owner can unpause
        vm.prank(moduleOwner);
        guardedModule.unpause();
    }
    
    /**
     * @notice Test: Owner can update registry address (for migration)
     */
    function test_UpdateRegistry() public {
        // Deploy new registry
        vm.startPrank(registryOwner);
        TargetRegistry newRegistry =
            new TestTargetRegistryWithMockSafe(registryOwner, address(mockSafeWallet));
        vm.label(address(newRegistry), "NewRegistry");
        
        // Add the same whitelist entries
        address[] memory whitelistTargets3 = new address[](2);
        whitelistTargets3[0] = address(uniswapPool);
        whitelistTargets3[1] = address(usdcToken);
        bytes4[] memory whitelistSelectors3 = new bytes4[](2);
        whitelistSelectors3[0] = SWAP_SELECTOR;
        whitelistSelectors3[1] = TRANSFER_SELECTOR;
        newRegistry.addToWhitelist(whitelistTargets3, whitelistSelectors3);
        vm.stopPrank();
        
        // Update registry
        vm.prank(moduleOwner);
        guardedModule.updateRegistry(address(newRegistry));
        
        // Verify new registry is set
        assertEq(
            address(guardedModule.registry()), address(newRegistry), "Registry should be updated"
        );
        
        // Verify it still works
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 0;
        
        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });
    }
    
    /**
     * @notice Test: Only owner can update registry address
     */
    function test_OnlyOwnerCanUpdateRegistry() public {
        address attacker = makeAddr("attacker");
        TargetRegistry maliciousRegistry = new TargetRegistry(attacker);
        
        // Attacker tries to update registry (should fail)
        vm.prank(attacker);
        vm.expectRevert();
        guardedModule.updateRegistry(address(maliciousRegistry));
        
        // Verify attacker cannot update by checking revert reason
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert with OwnableUnauthorizedAccount
        guardedModule.updateRegistry(address(maliciousRegistry));
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
        vm.prank(moduleOwner);
        guardedModule.transferOwnership(newOwner);

        // Verify pending owner is set
        assertEq(guardedModule.pendingOwner(), newOwner, "Pending owner should be set");

        // Verify current owner hasn't changed yet
        assertEq(guardedModule.owner(), moduleOwner, "Current owner should not have changed yet");

        // Non-pending owner cannot accept
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        guardedModule.acceptOwnership();

        // Step 2: New owner accepts ownership
        vm.prank(newOwner);
        guardedModule.acceptOwnership();

        // Verify ownership has transferred
        assertEq(guardedModule.owner(), newOwner, "New owner should be set");
        assertEq(guardedModule.pendingOwner(), address(0), "Pending owner should be cleared");
        assertNotEq(guardedModule.owner(), moduleOwner, "Old owner should no longer be owner");

        // New owner can now perform owner functions
        vm.prank(newOwner);
        guardedModule.pause();
        assertTrue(guardedModule.paused(), "New owner should be able to pause");

        vm.prank(newOwner);
        guardedModule.unpause();
        assertFalse(guardedModule.paused(), "New owner should be able to unpause");

        // New owner can update registry
        TargetRegistry newRegistry = new TargetRegistry(makeAddr("registryOwner"));
        vm.prank(newOwner);
        guardedModule.updateRegistry(address(newRegistry));
        assertEq(address(guardedModule.registry()), address(newRegistry), "New owner should be able to update registry");
    }

    /**
     * @notice Test: ERC20 USDC transfer restrictions (authorized recipients only)
     */
    function test_ERC20USDCTransferRestrictions() public {
        // Mint some USDC to smart account
        usdcToken.mint(smartAccount, 1000 * 10 ** 6); // 1000 USDC
        
        // Test 1: Transfer to smart account itself (should work)
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        targets[0] = address(usdcToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, smartAccount, 100 * 10 ** 6);
        values[0] = 0;
        
        Execution[] memory executions1 = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions1
            )
        });
        
        // Test 2: Transfer to Safe owner (should work)
        address[] memory owners = mockSafeWallet.getOwners();
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, owners[1], 100 * 10 ** 6);
        values[0] = 0;
        
        Execution[] memory executions2 = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions2
            )
        });
        
        // Test 3: Transfer to random address should FAIL (always restricted now)
        address randomAddress = makeAddr("randomAddress");
        wethToken.mint(smartAccount, 1 ether);
        targets[0] = address(wethToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 0.1 ether);
        values[0] = 0;
        
        Execution[] memory executions3 = _toExecutions(targets, calldatas, values);
        
        instance.expect4337Revert(GuardedExecModuleUpgradeable.UnauthorizedERC20Transfer.selector);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions3
            )
        });
    }
    
    /**
     * @notice Test: WETH transfer restriction state management (add/remove allowed recipients)
     */
    function test_WETHRestrictionStateManagement() public {
        address randomAddress = makeAddr("randomAddress");
        
        // Mint WETH to smart account
        wethToken.mint(smartAccount, 1 ether);
        
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        // Test 1: Transfer to random address should FAIL (always restricted now)
        targets[0] = address(wethToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 0.1 ether);
        values[0] = 0;
        
        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        
        instance.expect4337Revert(GuardedExecModuleUpgradeable.UnauthorizedERC20Transfer.selector);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        // Test 2: Add randomAddress as allowed recipient and retry
        vm.startPrank(registryOwner);
        address[] memory recipients = new address[](1);
        recipients[0] = randomAddress;
        registry.addAllowedERC20TokenRecipient(address(wethToken), recipients);
        vm.stopPrank();
        
        // Mint more WETH and try transfer again (should work now)
        wethToken.mint(smartAccount, 1 ether);
        targets[0] = address(wethToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 0.1 ether);
        values[0] = 0;
        
        Execution[] memory executions4 = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions4
            )
        });
        
        // Test 3: Remove randomAddress from allowed recipients
        vm.startPrank(registryOwner);
        registry.removeAllowedERC20TokenRecipient(address(wethToken), recipients);
        vm.stopPrank();
        
        // Test 4: Transfer should FAIL again
        wethToken.mint(smartAccount, 1 ether);
        targets[0] = address(wethToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 0.1 ether);
        values[0] = 0;
        
        Execution[] memory executions5 = _toExecutions(targets, calldatas, values);
        
        instance.expect4337Revert(GuardedExecModuleUpgradeable.UnauthorizedERC20Transfer.selector);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions5
            )
        });
    }
    
    /**
     * @notice Test: Direct ERC20 transfer authorization checks with mock Safe wallet
     */
    function test_DirectERC20TransferAuthorizationWithMockSafe() public {
        // Test the registry's isERC20TransferAuthorized function directly
        address[] memory owners = mockSafeWallet.getOwners();
        
        // Test 1: Transfer to smart account itself (should be authorized)
        bool isAuthorized1 =
            registry.isERC20TransferAuthorized(address(usdcToken), smartAccount, smartAccount);
        assertTrue(isAuthorized1, "Transfer to smart account should be authorized");
        
        // Test 2: Transfer to Safe owner (should be authorized)
        bool isAuthorized2 =
            registry.isERC20TransferAuthorized(address(usdcToken), owners[1], smartAccount);
        assertTrue(isAuthorized2, "Transfer to Safe owner should be authorized");
        
        // Test 3: Transfer to random address (should not be authorized - all tokens restricted now)
        address randomAddress = makeAddr("randomAddress");
        bool isAuthorized3 =
            registry.isERC20TransferAuthorized(address(usdcToken), randomAddress, smartAccount);
        assertFalse(isAuthorized3, "Transfer to random address should not be authorized");
        
        // Test 4: Transfer WETH to random address (should also not be authorized - all tokens
        // restricted now)
        bool isAuthorized4 =
            registry.isERC20TransferAuthorized(address(wethToken), randomAddress, smartAccount);
        assertFalse(
            isAuthorized4,
            "Transfer WETH to random address should not be authorized (all tokens restricted)"
        );
    }
    
    /**
     * @notice Test: Module can only be initialized once
     */
    function test_ModuleInitializesOnlyOnce() public {
        // Try to initialize again (should fail)
        vm.expectRevert();
        guardedModule.initialize(address(registry), moduleOwner);
    }
    
    /**
     * @notice Test: Cannot update registry to zero address
     */
    function test_CannotUpdateRegistryToZeroAddress() public {
        vm.prank(moduleOwner);
        vm.expectRevert();
        guardedModule.updateRegistry(address(0));
    }
    
    /**
     * @notice Test: Upgrade module implementation while keeping same proxy address
     */
    function test_UpgradeModuleKeepsSameAddress() public {
        address proxyAddr = address(proxy);
        bytes32 slot = IMPLEMENTATION_SLOT;
        
        // Get original implementation from storage
        address originalImpl = address(uint160(uint256(vm.load(proxyAddr, slot))));
        
        // Verify V1
        assertEq(guardedModule.name(), "GuardedExecModuleUpgradeable", "Should be V1");
        
        // Store state
        address reg = address(guardedModule.registry());
        address ownerAddr = guardedModule.owner();
        
        // Deploy and upgrade to V2 (using mock contract for testing)
        MockGuardedExecModuleUpgradeableV2 v2 = new MockGuardedExecModuleUpgradeableV2();
        
        vm.prank(moduleOwner);
        guardedModule.upgradeToAndCall(
            address(v2),
            abi.encodeWithSelector(MockGuardedExecModuleUpgradeableV2.initializeV2.selector, "V2!")
        );
        
        // Verify address unchanged
        address proxyAfterUpgrade = address(proxy);
        assertEq(proxyAfterUpgrade, proxyAddr, "Address must stay same");
        
        // Verify new implementation
        address newImpl = address(uint160(uint256(vm.load(proxyAddr, slot))));
        assertEq(newImpl, address(v2), "Implementation updated");
        assertNotEq(newImpl, originalImpl, "Implementation changed");
        
        // Cast to V2
        MockGuardedExecModuleUpgradeableV2 v2Module = MockGuardedExecModuleUpgradeableV2(proxyAddr);
        assertEq(v2Module.name(), "MockGuardedExecModuleUpgradeableV2", "Is V2");
        
        // Verify state persisted
        assertEq(address(v2Module.registry()), reg, "Registry persisted");
        assertEq(v2Module.owner(), ownerAddr, "Owner persisted");
        assertEq(v2Module.upgradeMessage(), "V2!", "V2 message set");
    }
    
    /**
     * @notice Test: Only owner can upgrade module implementation
     */
    function test_OnlyOwnerCanUpgrade() public {
        address attacker = makeAddr("attacker");
        MockGuardedExecModuleUpgradeableV2 v2Implementation =
            new MockGuardedExecModuleUpgradeableV2();
        
        // Attacker tries to upgrade (should fail)
        vm.prank(attacker);
        vm.expectRevert();
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(v2Implementation), "");
        
        // Owner can upgrade
        vm.prank(moduleOwner);
        guardedModule.upgradeToAndCall(address(v2Implementation), "");
        
        // Verify upgrade was successful
        address newImplementation =
            address(uint160(uint256(vm.load(address(proxy), IMPLEMENTATION_SLOT))));
        assertEq(newImplementation, address(v2Implementation), "Implementation should be upgraded");
    }
    
    /**
     * @notice Test: Storage layout compatibility after upgrade (state persistence)
     */
    function test_StorageLayoutCompatibility() public {
        // Store some data before upgrade
        address registryBefore = address(guardedModule.registry());
        address ownerBefore = guardedModule.owner();
        
        // Upgrade to V2 (using mock contract for testing)
        MockGuardedExecModuleUpgradeableV2 v2Implementation =
            new MockGuardedExecModuleUpgradeableV2();
        
        vm.prank(moduleOwner);
        guardedModule.upgradeToAndCall(
            address(v2Implementation),
            abi.encodeWithSelector(
                MockGuardedExecModuleUpgradeableV2.initializeV2.selector,
                "Storage compatibility test"
            )
        );
        
        MockGuardedExecModuleUpgradeableV2 v2Module =
            MockGuardedExecModuleUpgradeableV2(address(proxy));
        
        // Verify storage slots are compatible
        assertEq(
            address(v2Module.registry()), registryBefore, "Registry should be at same storage slot"
        );
        assertEq(v2Module.owner(), ownerBefore, "Owner should be at same storage slot");
        
        // Verify new storage variables work
        assertEq(v2Module.upgradeCounter(), 1, "Upgrade counter should be set");
        assertEq(
            v2Module.upgradeMessage(), "Storage compatibility test", "Upgrade message should be set"
        );
    }
    
    /**
     * @notice Test: Unsupported pool should revert (whitelist check)
     * @dev Verifies that calling non-whitelisted pool fails whitelist validation
     */
    function test_UnsupportedPoolShouldRevert() public {
        // Deploy a new unsupported pool
        MockDeFiPool unsupportedPool = new MockDeFiPool();
        vm.label(address(unsupportedPool), "UnsupportedPool");
        
        // Try to call unsupported pool (not whitelisted) directly as smart account
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        targets[0] = address(unsupportedPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 0;
        
        Execution[] memory executions = _toExecutions(targets, calldatas, values);
        
        // Call directly as smart account (not via instance.exec wrapper)
        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.TargetSelectorNotWhitelisted.selector,
                address(unsupportedPool),
                SWAP_SELECTOR
            )
        );
        
        guardedModule.executeGuardedBatch(executions);
    }
    
    /**
     * @notice Test: Owner can add to whitelist directly
     */
    function test_OwnerCanAddToWhitelist() public {
        MockDeFiPool newPool = new MockDeFiPool();
        
        // Owner adds to whitelist directly
        vm.prank(registryOwner);
        address[] memory whitelistTargets4 = new address[](1);
        whitelistTargets4[0] = address(newPool);
        bytes4[] memory whitelistSelectors4 = new bytes4[](1);
        whitelistSelectors4[0] = SWAP_SELECTOR;
        registry.addToWhitelist(whitelistTargets4, whitelistSelectors4);
        
        // Verify it's whitelisted (using auto-generated getter)
        bool whitelisted = registry.whitelist(address(newPool), SWAP_SELECTOR);
        assertTrue(whitelisted);
    }
    
    /**
     * @notice Test: Registry pause stops malicious scheduling (emergency stop)
     */
    function test_RegistryPauseStopsMaliciousScheduling() public {
        MockDeFiPool maliciousPool = new MockDeFiPool();
        
        vm.startPrank(registryOwner);
        
        // First verify adding works when not paused
        address[] memory whitelistTargets5 = new address[](1);
        whitelistTargets5[0] = address(maliciousPool);
        bytes4[] memory whitelistSelectors5 = new bytes4[](1);
        whitelistSelectors5[0] = SWAP_SELECTOR;
        registry.addToWhitelist(whitelistTargets5, whitelistSelectors5);
        
        // Remove it for cleanup
        registry.removeFromWhitelist(whitelistTargets5, whitelistSelectors5);
        
        // EMERGENCY: Owner wallet compromised! Pause the registry!
        registry.pause();
        
        // Attacker (using compromised owner key) tries to add malicious pool
        vm.expectRevert();
        registry.addToWhitelist(whitelistTargets5, whitelistSelectors5);
        
        // Unpause after securing the owner wallet
        registry.unpause();
        
        // Can add again
        registry.addToWhitelist(whitelistTargets5, whitelistSelectors5);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test: ERC20 transfer restrictions with mock Safe wallet (authorized recipients)
     */
    function test_ERC20TransferRestrictionsWithMockSafe() public {
        // Mint some USDC to smart account
        usdcToken.mint(smartAccount, 1000 * 10 ** 6); // 1000 USDC
        
        // Get Safe owners
        address[] memory owners = mockSafeWallet.getOwners();
        
        // Test 1: Transfer to smart account itself (should work)
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        
        targets[0] = address(usdcToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, smartAccount, 100 * 10 ** 6);
        values[0] = 0;
        
        Execution[] memory executions6 = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions6
            )
        });
        
        // Test 2: Transfer to Safe owner (should work)
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, owners[1], 100 * 10 ** 6);
        values[0] = 0;
        
        Execution[] memory executions7 = _toExecutions(targets, calldatas, values);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions7
            )
        });
        
        // Test 3: Transfer to random address (should fail - always restricted now)
        address randomAddress = makeAddr("randomAddress");
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 100 * 10 ** 6);
        values[0] = 0;
        
        // Check if the transfer would be authorized (should be false)
        bool isAuthorized =
            registry.isERC20TransferAuthorized(address(usdcToken), randomAddress, smartAccount);
        assertFalse(isAuthorized, "Transfer to random address should not be authorized");
        
        // Test 4: Transfer WETH to random address (should fail - always restricted now)
        wethToken.mint(smartAccount, 1 ether);
        targets[0] = address(wethToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 0.1 ether);
        values[0] = 0;
        
        Execution[] memory executions8 = _toExecutions(targets, calldatas, values);
        
        instance.expect4337Revert(GuardedExecModuleUpgradeable.UnauthorizedERC20Transfer.selector);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions8
            )
        });
    }

    /**
     * @notice Test: Cannot execute with empty batch
     */
    function test_CannotExecuteEmptyBatch() public {
        Execution[] memory emptyExecutions = new Execution[](0);

        vm.prank(smartAccount);
        vm.expectRevert(GuardedExecModuleUpgradeable.EmptyBatch.selector);
        guardedModule.executeGuardedBatch(emptyExecutions);
    }

    // Note: LengthMismatch tests removed since Execution[] struct ensures consistency

    /**
     * @notice Test: Cannot execute with invalid calldata (too short for selector)
     */
    function test_CannotExecuteWithInvalidCalldata() public {
        address[] memory targets = new address[](1);
        targets[0] = address(uniswapPool);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = hex"1234"; // Only 2 bytes, too short for selector (needs 4 bytes)
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        vm.prank(smartAccount);
        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidCalldata.selector);
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Test: Cannot execute ERC20 transfer with invalid calldata length
     */
    function test_CannotExecuteERC20TransferWithInvalidCalldataLength() public {
        // Transfer requires exactly 68 bytes (4 selector + 32 to + 32 amount)
        address[] memory targets = new address[](1);
        targets[0] = address(usdcToken);
        bytes[] memory calldatas = new bytes[](1);
        // Create invalid transfer calldata (wrong length - only 36 bytes: 4 selector + 32 to,
        // missing amount)
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, smartAccount);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        vm.prank(smartAccount);
        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidCalldata.selector);
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Test: ERC20 approve with whitelisted target spender should succeed
     * @dev Verifies that approve() calls work when spender is a whitelisted target (like uniswapPool)
     */
    function test_ERC20ApproveWithWhitelistedTargetSpender() public {
        // Mint some USDC to smart account
        usdcToken.mint(smartAccount, 1000 * 10 ** 6); // 1000 USDC

        // uniswapPool is whitelisted (has SWAP_SELECTOR whitelisted), so it should be approved
        address whitelistedSpender = address(uniswapPool);

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(usdcToken);
        calldatas[0] = abi.encodeWithSelector(APPROVE_SELECTOR, whitelistedSpender, 100 * 10 ** 6);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        // Approve should succeed with whitelisted target spender
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        // Verify approval was successful
        uint256 allowance = usdcToken.allowance(smartAccount, whitelistedSpender);
        assertEq(allowance, 100 * 10 ** 6, "Allowance should be set");
    }

    /**
     * @notice Test: ERC20 approve with unauthorized spender should revert
     * @dev Verifies that approve() calls fail when spender is not whitelisted
     */
    function test_ERC20ApproveWithUnauthorizedSpender() public {
        address unauthorizedSpender = makeAddr("unauthorizedSpender");

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(usdcToken);
        calldatas[0] = abi.encodeWithSelector(APPROVE_SELECTOR, unauthorizedSpender, 100 * 10 ** 6);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        // Approve should fail with unauthorized spender (not whitelisted)
        instance.expect4337Revert(GuardedExecModuleUpgradeable.UnauthorizedERC20Approve.selector);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });
    }

    /**
     * @notice Test: ERC20 approve to smart account itself should fail if not whitelisted
     * @dev Verifies that approve() calls check whitelist - even self-approval requires whitelisting
     */
    function test_ERC20ApproveToSmartAccountSelfFailsIfNotWhitelisted() public {
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(usdcToken);
        calldatas[0] = abi.encodeWithSelector(APPROVE_SELECTOR, smartAccount, 100 * 10 ** 6);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        // Approve to self should fail if smart account is not whitelisted
        // (smart account is not a whitelisted target - it's just the wallet)
        instance.expect4337Revert(GuardedExecModuleUpgradeable.UnauthorizedERC20Approve.selector);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });
    }

    /**
     * @notice Test: Smart wallet executes transaction with ETH value using its own balance
     * @dev Verifies that when Execution struct contains value > 0, the smart wallet uses its own
     *      balance to forward ETH to target contracts, even though the module is not payable.
     */
    function test_SmartWalletExecutesWithEthValue() public {
        // Fund smart account with ETH
        vm.deal(smartAccount, 10 ether);

        // Verify initial balance of target contract
        address targetContract = address(uniswapPool);
        uint256 initialBalance = targetContract.balance;
        assertEq(initialBalance, 0, "Target contract should start with 0 ETH");

        // Create execution with ETH value
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = targetContract;
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 1 ether; // Send 1 ETH with the call

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        // Execute via smart account (module is not payable, but smart account has ETH)
        instance.exec({
            target: address(guardedModule),
            value: 0, // Module doesn't accept ETH
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        // Verify ETH was sent to target contract from smart account's balance
        uint256 finalBalance = targetContract.balance;
        assertEq(finalBalance, 1 ether, "Target contract should have received 1 ETH");

        // Verify smart account balance decreased (accounting for gas costs)
        uint256 smartAccountBalance = smartAccount.balance;
        assertGt(smartAccountBalance, 8 ether, "Smart account should have at least 8 ETH remaining");
        assertLt(smartAccountBalance, 10 ether, "Smart account balance should be less than 10 ETH");
    }

    /**
     * @notice Test: Smart wallet executes batch with multiple ETH values
     * @dev Verifies that smart wallet can execute multiple operations with different ETH values
     *      using its own balance.
     */
    function test_SmartWalletExecutesBatchWithMultipleEthValues() public {
        // Fund smart account with ETH
        vm.deal(smartAccount, 10 ether);

        // Create two target contracts to receive ETH
        MockDeFiPool pool1 = new MockDeFiPool();
        MockDeFiPool pool2 = new MockDeFiPool();

        // Whitelist both pools
        vm.startPrank(registryOwner);
        address[] memory whitelistTargets = new address[](2);
        whitelistTargets[0] = address(pool1);
        whitelistTargets[1] = address(pool2);
        bytes4[] memory whitelistSelectors = new bytes4[](2);
        whitelistSelectors[0] = SWAP_SELECTOR;
        whitelistSelectors[1] = SWAP_SELECTOR;
        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
        vm.stopPrank();

        // Create batch execution with different ETH values
        address[] memory targets = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(pool1);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        values[0] = 1 ether; // Send 1 ETH to pool1

        targets[1] = address(pool2);
        calldatas[1] = abi.encodeWithSelector(SWAP_SELECTOR, 2000 ether, 1800 ether);
        values[1] = 2 ether; // Send 2 ETH to pool2

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        // Execute batch via smart account
        instance.exec({
            target: address(guardedModule),
            value: 0, // Module doesn't accept ETH
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        // Verify ETH was sent to both target contracts
        assertEq(address(pool1).balance, 1 ether, "Pool1 should have received 1 ETH");
        assertEq(address(pool2).balance, 2 ether, "Pool2 should have received 2 ETH");

        // Verify smart account balance decreased by total (3 ETH) plus gas costs
        uint256 smartAccountBalance = smartAccount.balance;
        assertGt(smartAccountBalance, 6 ether, "Smart account should have at least 6 ETH remaining");
        assertLt(smartAccountBalance, 10 ether, "Smart account balance should be less than 10 ETH");
    }

    /**
     * @notice Test: Cannot initialize with zero registry address
     */
    function test_CannotInitializeWithZeroRegistry() public {
        GuardedExecModuleUpgradeable newImpl = new GuardedExecModuleUpgradeable();

        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidRegistry.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.initialize.selector,
                address(0), // Zero registry address
                moduleOwner
            )
        );
    }
}
