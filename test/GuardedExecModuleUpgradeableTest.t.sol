// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { RhinestoneModuleKit, ModuleKitHelpers, AccountInstance } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/accounts/common/interfaces/IERC7579Module.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { MockDeFiPool } from "test/mocks/MockDeFiPool.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockAaveV4Spoke } from "test/mocks/MockAaveV4Spoke.sol";
import { MockComet } from "test/mocks/MockComet.sol";
import { MockIporWithdrawManager, MockPlasmaVaultShares } from
    "test/mocks/MockIporWithdrawManager.sol";
import { MockMorphoBlue } from "test/mocks/MockMorphoBlue.sol";
import { MockOperatorVault } from "test/mocks/MockOperatorVault.sol";
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

    // Production Zyfai Adapter proxy (same address on Ethereum, Base, Arbitrum)
    address internal constant ADAPTER = 0xaffD3c3cD06cf499deddf78b26868018A93f2C31;

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
        implementation = new GuardedExecModuleUpgradeable(ADAPTER);
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

        assertEq(guardedModule.ADAPTER(), ADAPTER, "Adapter is read from the implementation");
        
        // Check version
        string memory version = guardedModule.version();
        assertEq(version, "2.1.0", "Version should be 2.1.0");
        
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
     * @notice Test: Module owner cannot renounce ownership
     */
    function test_RenounceOwnershipDisabled() public {
        vm.prank(moduleOwner);
        vm.expectRevert(GuardedExecModuleUpgradeable.RenounceOwnershipDisabled.selector);
        guardedModule.renounceOwnership();
        assertEq(guardedModule.owner(), moduleOwner, "owner unchanged");
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
     * @notice Regression: an allowance to a spender removed from the registry can still be
     *         cleared with approve(spender, 0), while a non-zero approve to it still reverts
     */
    function test_ERC20ApproveZeroClearsAllowanceOfDelistedSpender() public {
        address spender = address(uniswapPool);
        Execution[] memory grant = _singleExecution(
            address(usdcToken), abi.encodeWithSelector(APPROVE_SELECTOR, spender, 100e6)
        );
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(grant);
        assertEq(usdcToken.allowance(smartAccount, spender), 100e6, "allowance granted");

        address[] memory delistTargets = new address[](1);
        bytes4[] memory delistSelectors = new bytes4[](1);
        delistTargets[0] = spender;
        delistSelectors[0] = SWAP_SELECTOR;
        vm.prank(registryOwner);
        registry.removeFromWhitelist(delistTargets, delistSelectors);
        assertFalse(registry.whitelistedTargets(spender), "spender delisted");

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.UnauthorizedERC20Approve.selector,
                address(usdcToken),
                spender
            )
        );
        guardedModule.executeGuardedBatch(grant);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(usdcToken), abi.encodeWithSelector(APPROVE_SELECTOR, spender, 0)
            )
        );
        assertEq(usdcToken.allowance(smartAccount, spender), 0, "allowance cleared");
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
        GuardedExecModuleUpgradeable newImpl = new GuardedExecModuleUpgradeable(ADAPTER);

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

    /**
     * @notice Test: Cannot deploy an implementation with a zero Adapter address
     */
    function test_CannotDeployImplementationWithZeroAdapter() public {
        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidAdapter.selector);
        new GuardedExecModuleUpgradeable(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                 SETAUTHORIZATION GRANT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    bytes4 internal constant SET_AUTHORIZATION_SELECTOR = MockMorphoBlue.setAuthorization.selector;

    /**
     * @notice Deploy a mock Morpho Blue singleton and whitelist (morpho, setAuthorization)
     */
    function _deployAndWhitelistMorpho() internal returns (MockMorphoBlue morpho) {
        morpho = new MockMorphoBlue();
        vm.label(address(morpho), "MockMorphoBlue");

        vm.startPrank(registryOwner);
        address[] memory whitelistTargets = new address[](1);
        whitelistTargets[0] = address(morpho);
        bytes4[] memory whitelistSelectors = new bytes4[](1);
        whitelistSelectors[0] = SET_AUTHORIZATION_SELECTOR;
        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
        vm.stopPrank();
    }

    /**
     * @notice Test: setAuthorization granting the Adapter succeeds
     */
    function test_SetAuthorizationGrantToAdapterSucceeds() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        targets[0] = address(morpho);
        calldatas[0] = abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, ADAPTER, true);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        assertTrue(
            morpho.isAuthorized(smartAccount, ADAPTER),
            "Smart account should have authorized the Adapter"
        );
    }

    /**
     * @notice Test: setAuthorization granting a whitelisted target other than the Adapter reverts
     * @dev A whitelisted token has no receiver binding; authorizing it would let anyone who can
     *      make it call Morpho act on the smart account's positions.
     */
    function test_SetAuthorizationGrantToWhitelistedTokenReverts() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();
        address grantee = address(usdcToken);
        assertTrue(registry.whitelistedTargets(grantee), "grantee is a whitelisted target");

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.UnauthorizedAuthorizationGrant.selector,
                address(morpho),
                grantee
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(morpho), abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, grantee, true)
            )
        );
    }

    /**
     * @notice Test: setAuthorization granting an arbitrary address reverts
     * @dev This is the drain path: a compromised session key tries to authorize its own EOA
     *      as global Morpho operator for the Safe. The module must block it.
     */
    function test_SetAuthorizationGrantToArbitraryAddressReverts() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();
        address attacker = makeAddr("attacker");

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        targets[0] = address(morpho);
        calldatas[0] = abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, attacker, true);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        instance.expect4337Revert(
            GuardedExecModuleUpgradeable.UnauthorizedAuthorizationGrant.selector
        );
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        assertFalse(
            morpho.isAuthorized(smartAccount, attacker),
            "Attacker must never become authorized"
        );
    }

    /**
     * @notice Test: granting then revoking (bool = false) the Adapter passes validation
     */
    function test_SetAuthorizationRevokeAdapterSucceeds() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();
        address adapter = ADAPTER;

        address[] memory targets = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        uint256[] memory values = new uint256[](2);
        targets[0] = address(morpho);
        calldatas[0] = abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, adapter, true);
        values[0] = 0;
        targets[1] = address(morpho);
        calldatas[1] = abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, adapter, false);
        values[1] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector, executions
            )
        });

        assertFalse(
            morpho.isAuthorized(smartAccount, adapter), "Authorization should have been revoked"
        );
    }

    /**
     * @notice Test: setAuthorization without a registry whitelist entry reverts
     */
    function test_SetAuthorizationNotWhitelistedSelectorReverts() public {
        MockMorphoBlue morpho = new MockMorphoBlue(); // NOT whitelisted

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        targets[0] = address(morpho);
        calldatas[0] =
            abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, address(uniswapPool), true);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.TargetSelectorNotWhitelisted.selector,
                address(morpho),
                SET_AUTHORIZATION_SELECTOR
            )
        );
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Test: malformed setAuthorization calldata (wrong length) reverts
     */
    function test_SetAuthorizationInvalidCalldataLengthReverts() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        targets[0] = address(morpho);
        // Only 36 bytes: 4 (selector) + 32 (address), missing the bool word
        calldatas[0] = abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, address(uniswapPool));
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        vm.prank(smartAccount);
        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidCalldata.selector);
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Fuzz: no grantee other than the Adapter can ever pass setAuthorization validation
     */
    function testFuzz_SetAuthorizationGrantOnlyAdapter(address grantee) public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();
        vm.assume(grantee != ADAPTER);

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        targets[0] = address(morpho);
        calldatas[0] = abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, grantee, true);
        values[0] = 0;

        Execution[] memory executions = _toExecutions(targets, calldatas, values);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.UnauthorizedAuthorizationGrant.selector,
                address(morpho),
                grantee
            )
        );
        guardedModule.executeGuardedBatch(executions);
    }

    function _singleExecution(
        address target,
        bytes memory callData
    )
        internal
        pure
        returns (Execution[] memory executions)
    {
        executions = new Execution[](1);
        executions[0] = Execution({ target: target, value: 0, callData: callData });
    }

    /**
     * @notice Test: a stale grant to a non-Adapter address (e.g. made under the previous
     *         whitelisted-target rule) can still be revoked
     */
    function test_SetAuthorizationRevokeNonAdapterGranteeSucceeds() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();
        address grantee = address(curvePool);

        vm.prank(smartAccount);
        morpho.setAuthorization(grantee, true);
        assertTrue(morpho.isAuthorized(smartAccount, grantee), "stale grant present");

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(morpho), abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, grantee, false)
            )
        );
        assertFalse(morpho.isAuthorized(smartAccount, grantee), "stale authorization revoked");
    }

    /**
     * @notice Test: a non-canonical bool word (2) is treated as a grant, not a revoke
     */
    function test_SetAuthorizationNonCanonicalBoolToArbitraryAddressReverts() public {
        MockMorphoBlue morpho = _deployAndWhitelistMorpho();
        address attacker = makeAddr("attacker");

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.UnauthorizedAuthorizationGrant.selector,
                address(morpho),
                attacker
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(morpho),
                abi.encodeWithSelector(SET_AUTHORIZATION_SELECTOR, attacker, uint256(2))
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                   SETOPERATOR GRANT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    bytes4 internal constant SET_OPERATOR_SELECTOR = MockOperatorVault.setOperator.selector;

    /**
     * @notice Deploy a mock ERC-7540 vault and whitelist (vault, setOperator)
     */
    function _deployAndWhitelistOperatorVault() internal returns (MockOperatorVault vault) {
        vault = new MockOperatorVault();
        vm.label(address(vault), "MockOperatorVault");

        vm.startPrank(registryOwner);
        address[] memory whitelistTargets = new address[](1);
        whitelistTargets[0] = address(vault);
        bytes4[] memory whitelistSelectors = new bytes4[](1);
        whitelistSelectors[0] = SET_OPERATOR_SELECTOR;
        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
        vm.stopPrank();
    }

    /**
     * @notice Test: setOperator granting the Adapter succeeds
     */
    function test_SetOperatorGrantToAdapterSucceeds() public {
        MockOperatorVault vault = _deployAndWhitelistOperatorVault();

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(vault), abi.encodeWithSelector(SET_OPERATOR_SELECTOR, ADAPTER, true)
            )
        );
        assertTrue(vault.isOperator(smartAccount, ADAPTER), "Adapter operator granted");
    }

    /**
     * @notice Test: setOperator granting a whitelisted target other than the Adapter reverts
     */
    function test_SetOperatorGrantToWhitelistedTokenReverts() public {
        MockOperatorVault vault = _deployAndWhitelistOperatorVault();
        address grantee = address(usdcToken);
        assertTrue(registry.whitelistedTargets(grantee), "grantee is a whitelisted target");

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.UnauthorizedAuthorizationGrant.selector,
                address(vault),
                grantee
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(vault), abi.encodeWithSelector(SET_OPERATOR_SELECTOR, grantee, true)
            )
        );
    }

    /**
     * @notice Test: setOperator granting an arbitrary address reverts
     */
    function test_SetOperatorGrantToArbitraryAddressReverts() public {
        MockOperatorVault vault = _deployAndWhitelistOperatorVault();
        address attacker = makeAddr("attacker");

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.UnauthorizedAuthorizationGrant.selector,
                address(vault),
                attacker
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(vault), abi.encodeWithSelector(SET_OPERATOR_SELECTOR, attacker, true)
            )
        );
        assertFalse(vault.isOperator(smartAccount, attacker), "attacker never an operator");
    }

    /**
     * @notice Test: setOperator revoke (false) of a non-whitelisted address succeeds
     */
    function test_SetOperatorRevokeArbitraryAddressSucceeds() public {
        MockOperatorVault vault = _deployAndWhitelistOperatorVault();
        address stale = makeAddr("stale");

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(vault), abi.encodeWithSelector(SET_OPERATOR_SELECTOR, stale, false)
            )
        );
        assertFalse(vault.isOperator(smartAccount, stale), "revoke passed");
    }

    /**
     * @notice Test: malformed setOperator calldata (wrong length) reverts
     */
    function test_SetOperatorInvalidCalldataLengthReverts() public {
        MockOperatorVault vault = _deployAndWhitelistOperatorVault();

        vm.prank(smartAccount);
        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidCalldata.selector);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(vault), abi.encodeWithSelector(SET_OPERATOR_SELECTOR, address(uniswapPool))
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                 AAVE V4 SPOKE MIN HEALTH FACTOR TESTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant MIN_HEALTH_FACTOR = 1.5e18;
    uint256 internal constant RESERVE_ID = 7;

    /**
     * @notice Deploy a mock Aave v4 Spoke and whitelist its five position selectors
     */
    function _deployAndWhitelistSpoke() internal returns (MockAaveV4Spoke spoke) {
        spoke = new MockAaveV4Spoke();
        vm.label(address(spoke), "MockAaveV4Spoke");

        vm.startPrank(registryOwner);
        address[] memory whitelistTargets = new address[](5);
        bytes4[] memory whitelistSelectors = new bytes4[](5);
        whitelistSelectors[0] = MockAaveV4Spoke.supply.selector;
        whitelistSelectors[1] = MockAaveV4Spoke.withdraw.selector;
        whitelistSelectors[2] = MockAaveV4Spoke.borrow.selector;
        whitelistSelectors[3] = MockAaveV4Spoke.repay.selector;
        whitelistSelectors[4] = MockAaveV4Spoke.setUsingAsCollateral.selector;
        for (uint256 i = 0; i < 5; i++) {
            whitelistTargets[i] = address(spoke);
        }
        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
        vm.stopPrank();
    }

    /// @notice Encode a Spoke (reserveId, amount, smartAccount) position call
    function _spokeCall(bytes4 selector, uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(selector, RESERVE_ID, amount, smartAccount);
    }

    /// @notice Expected getUserAccountData calldata for the smart account
    function _accountDataCall() internal view returns (bytes memory) {
        return abi.encodeCall(MockAaveV4Spoke.getUserAccountData, (smartAccount));
    }

    /**
     * @notice Test: a session-key borrow that leaves health factor exactly at the minimum passes
     */
    function test_SpokeBorrowAtMinHealthFactorSucceeds() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 0, true);

        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                _singleExecution(address(spoke), _spokeCall(MockAaveV4Spoke.borrow.selector, 2e18))
            )
        });

        assertEq(spoke.debt(smartAccount), 2e18, "borrow executed");
    }

    /**
     * @notice Test: a borrow leaving health factor below the minimum reverts the whole batch
     * @dev This is the self-liquidation path: a compromised session key borrows to the edge
     *      (the Spoke itself only enforces 1.0) and then liquidates the account from its own EOA.
     */
    function test_SpokeBorrowBelowMinHealthFactorRevertsWholeBatch() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 0, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(uniswapPool),
            value: 0,
            callData: abi.encodeWithSelector(SWAP_SELECTOR, 1 ether, 1 ether)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.borrow.selector, 2.5e18)
        });

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector, address(spoke), 1.2e18
            )
        );
        guardedModule.executeGuardedBatch(executions);

        assertEq(spoke.debt(smartAccount), 0, "borrow rolled back");
        (, uint256 swapCount) = uniswapPool.getLastCallInfo();
        assertEq(swapCount, 0, "earlier execution rolled back");
    }

    /**
     * @notice Test: withdrawing collateral below the minimum health factor reverts
     */
    function test_SpokeWithdrawBelowMinHealthFactorReverts() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 1e18, true);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector, address(spoke), 1.4e18
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(address(spoke), _spokeCall(MockAaveV4Spoke.withdraw.selector, 1.6e18))
        );

        assertEq(spoke.collateral(smartAccount), 3e18, "withdraw rolled back");
    }

    /**
     * @notice Test: setUsingAsCollateral(false) dropping health factor below the minimum reverts
     */
    function test_SpokeDisableCollateralBelowMinHealthFactorReverts() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 1e18, true);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector, address(spoke), 0
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(spoke),
                abi.encodeWithSelector(
                    MockAaveV4Spoke.setUsingAsCollateral.selector, RESERVE_ID, false, smartAccount
                )
            )
        );

        assertTrue(spoke.usingAsCollateral(smartAccount), "collateral toggle rolled back");
    }

    /**
     * @notice Test: supply and repay never trigger the health factor check, even below the minimum
     */
    function test_SpokeSupplyAndRepaySkipHealthFactorCheck() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.1e18, 1e18, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.supply.selector, 0.1e18)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.repay.selector, 0.1e18)
        });

        vm.expectCall(address(spoke), _accountDataCall(), 0);
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(executions);

        assertEq(spoke.collateral(smartAccount), 1.2e18, "supply executed");
        assertEq(spoke.debt(smartAccount), 0.9e18, "repay executed");
    }

    /**
     * @notice Test: the check runs once per Spoke at the end of the batch, so borrow-then-repay
     *         passes even though the intermediate health factor is below the minimum
     */
    function test_SpokeBorrowThenRepayChecksFinalHealthFactorOnce() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 0, true);

        Execution[] memory executions = new Execution[](3);
        executions[0] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.borrow.selector, 2.5e18)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.borrow.selector, 0.5e18)
        });
        executions[2] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.repay.selector, 1.5e18)
        });

        vm.expectCall(address(spoke), _accountDataCall(), 1);
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(executions);

        assertEq(spoke.debt(smartAccount), 1.5e18, "final debt");
    }

    /**
     * @notice Test: withdrawing everything with no debt passes (health factor is uint256 max)
     */
    function test_SpokeWithdrawWithoutDebtSucceeds() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 0, true);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(spoke), _spokeCall(MockAaveV4Spoke.withdraw.selector, type(uint256).max)
            )
        );

        assertEq(spoke.collateral(smartAccount), 0, "full withdraw executed");
    }

    /**
     * @notice Test: every Spoke touched in a batch is checked, not only the first
     */
    function test_SpokeHealthFactorCheckedOnEverySpoke() public {
        MockAaveV4Spoke spokeA = _deployAndWhitelistSpoke();
        MockAaveV4Spoke spokeB = _deployAndWhitelistSpoke();
        spokeA.setPosition(smartAccount, 3e18, 0, true);
        spokeB.setPosition(smartAccount, 3e18, 0, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(spokeA),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.borrow.selector, 1e18)
        });
        executions[1] = Execution({
            target: address(spokeB),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.borrow.selector, 2.5e18)
        });

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector, address(spokeB), 1.2e18
            )
        );
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Fuzz: a borrow passes iff the resulting health factor is >= MIN_HEALTH_FACTOR
     * @dev Collateral factor is 1 and debt is 1e18, so the resulting health factor equals
     *      `collateral`.
     */
    function testFuzz_SpokeBorrowMinHealthFactorBoundary(uint256 collateral) public {
        collateral = bound(collateral, 1e18, 3e18);
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, collateral, 0, true);

        if (collateral < MIN_HEALTH_FACTOR) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    GuardedExecModuleUpgradeable.HealthFactorTooLow.selector,
                    address(spoke),
                    collateral
                )
            );
        }
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(spoke), _spokeCall(MockAaveV4Spoke.borrow.selector, 1e18))
        );

        assertEq(spoke.debt(smartAccount), collateral < MIN_HEALTH_FACTOR ? 0 : 1e18, "debt");
    }

    function _healthFactorOf(MockAaveV4Spoke spoke) internal view returns (uint256) {
        return spoke.getUserAccountData(smartAccount).healthFactor;
    }

    /**
     * @notice Test: below the minimum, a batch without borrow that raises the health factor
     *         passes (deleverage: withdraw collateral, repay more debt), 1.2 -> 1.375
     */
    function test_SpokeDeleverageBelowMinHealthFactorSucceeds() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.2e18, 1e18, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.withdraw.selector, 0.1e18)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.repay.selector, 0.2e18)
        });
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(executions);

        assertEq(_healthFactorOf(spoke), 1.375e18, "health factor raised, still below 1.5");
    }

    /**
     * @notice Test: below the minimum, enabling collateral passes (0 -> 1.2)
     */
    function test_SpokeEnableCollateralBelowMinHealthFactorSucceeds() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.2e18, 1e18, false);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(
                address(spoke),
                abi.encodeWithSelector(
                    MockAaveV4Spoke.setUsingAsCollateral.selector, RESERVE_ID, true, smartAccount
                )
            )
        );

        assertEq(_healthFactorOf(spoke), 1.2e18, "collateral enabled");
    }

    /**
     * @notice Test: below the minimum, a batch without borrow that leaves the health factor
     *         unchanged passes (e.g. withdrawing funds that do not count as collateral)
     */
    function test_SpokeUnchangedHealthFactorBelowMinSucceeds() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.2e18, 1e18, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.withdraw.selector, 0.1e18)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.supply.selector, 0.1e18)
        });
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(executions);

        assertEq(_healthFactorOf(spoke), 1.2e18, "health factor unchanged");
    }

    /**
     * @notice Test: below the minimum, a batch that lowers the health factor still reverts
     */
    function test_SpokeWithdrawLoweringHealthFactorBelowMinReverts() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.2e18, 1e18, true);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector, address(spoke), 1.1e18
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(address(spoke), _spokeCall(MockAaveV4Spoke.withdraw.selector, 0.1e18))
        );
    }

    /**
     * @notice Test: a batch that borrows must end at the minimum even if it raises the health
     *         factor; otherwise a key could pull more collateral into a position near
     *         liquidation and borrow against it (1.2 -> 1.47 with supply + borrow)
     */
    function test_SpokeBorrowBelowMinRevertsEvenWhenHealthFactorRises() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.2e18, 1e18, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.supply.selector, 1e18)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.borrow.selector, 0.5e18)
        });
        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector,
                address(spoke),
                uint256(2.2e18) * 1e18 / 1.5e18
            )
        );
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Fuzz: a batch without borrow never leaves the health factor below both the
     *         minimum and its starting value
     */
    function testFuzz_SpokeNoBorrowBatchNeverLowersRisk(uint256 withdrawn, uint256 repaid) public {
        withdrawn = bound(withdrawn, 1, 1.2e18);
        repaid = bound(repaid, 1, 1e18);
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 1.2e18, 1e18, true);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.withdraw.selector, withdrawn)
        });
        executions[1] = Execution({
            target: address(spoke),
            value: 0,
            callData: _spokeCall(MockAaveV4Spoke.repay.selector, repaid)
        });
        vm.prank(smartAccount);
        try guardedModule.executeGuardedBatch(executions) { } catch { }

        assertGe(_healthFactorOf(spoke), 1.2e18, "health factor below its starting value");
    }

    /**
     * @notice Test: the owner sets a per-Spoke minimum; other Spokes keep the default, and 0
     *         restores the default
     */
    function test_SetMinHealthFactorPerSpoke() public {
        MockAaveV4Spoke spokeA = _deployAndWhitelistSpoke();
        MockAaveV4Spoke spokeB = _deployAndWhitelistSpoke();
        spokeA.setPosition(smartAccount, 1.8e18, 0, true);
        spokeB.setPosition(smartAccount, 1.8e18, 0, true);
        Execution[] memory borrowA =
            _singleExecution(address(spokeA), _spokeCall(MockAaveV4Spoke.borrow.selector, 1e18));

        vm.expectEmit(address(guardedModule));
        emit GuardedExecModuleUpgradeable.MinHealthFactorUpdated(address(spokeA), 2e18);
        vm.prank(moduleOwner);
        guardedModule.setMinHealthFactor(address(spokeA), 2e18);
        assertEq(guardedModule.minHealthFactor(address(spokeA)), 2e18, "spoke A minimum");
        assertEq(guardedModule.minHealthFactor(address(spokeB)), 1.5e18, "spoke B default");

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.HealthFactorTooLow.selector, address(spokeA), 1.8e18
            )
        );
        guardedModule.executeGuardedBatch(borrowA);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(spokeB), _spokeCall(MockAaveV4Spoke.borrow.selector, 1e18))
        );

        vm.prank(moduleOwner);
        guardedModule.setMinHealthFactor(address(spokeA), 0);
        assertEq(guardedModule.minHealthFactor(address(spokeA)), 1.5e18, "default restored");
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(borrowA);
    }

    /**
     * @notice Test: only the owner can set a minimum, it cannot go below 1.1, and
     *         type(uint256).max makes the Spoke lend-only for session keys
     */
    function test_SetMinHealthFactorOnlyOwnerAndBounds() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 0, true);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector, smartAccount
            )
        );
        guardedModule.setMinHealthFactor(address(spoke), 2e18);

        vm.startPrank(moduleOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.InvalidMinHealthFactor.selector, 1.1e18 - 1
            )
        );
        guardedModule.setMinHealthFactor(address(spoke), 1.1e18 - 1);
        guardedModule.setMinHealthFactor(address(spoke), 1.1e18);
        guardedModule.setMinHealthFactor(address(spoke), type(uint256).max);
        vm.stopPrank();

        vm.prank(smartAccount);
        vm.expectPartialRevert(GuardedExecModuleUpgradeable.HealthFactorTooLow.selector);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(spoke), _spokeCall(MockAaveV4Spoke.borrow.selector, 1e18))
        );

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(spoke), _spokeCall(MockAaveV4Spoke.withdraw.selector, 1e18))
        );
    }

    /**
     * @notice Test: all five Spoke position calls must name the smart account as onBehalfOf
     *         and have the exact (uint256, uint256|bool, address) length
     */
    function test_SpokeCallsRequireSmartAccountOnBehalfOf() public {
        MockAaveV4Spoke spoke = _deployAndWhitelistSpoke();
        spoke.setPosition(smartAccount, 3e18, 1e18, true);
        address attacker = makeAddr("spokeAttacker");
        bytes4[5] memory spokeSelectors = [
            MockAaveV4Spoke.supply.selector,
            MockAaveV4Spoke.withdraw.selector,
            MockAaveV4Spoke.borrow.selector,
            MockAaveV4Spoke.repay.selector,
            MockAaveV4Spoke.setUsingAsCollateral.selector
        ];

        for (uint256 i = 0; i < spokeSelectors.length; i++) {
            vm.prank(smartAccount);
            vm.expectRevert(
                abi.encodeWithSelector(
                    GuardedExecModuleUpgradeable.SpokeOnBehalfOfNotAccount.selector,
                    address(spoke),
                    attacker
                )
            );
            guardedModule.executeGuardedBatch(
                _singleExecution(
                    address(spoke),
                    abi.encodeWithSelector(spokeSelectors[i], RESERVE_ID, 1, attacker)
                )
            );

            vm.prank(smartAccount);
            vm.expectRevert(GuardedExecModuleUpgradeable.InvalidCalldata.selector);
            guardedModule.executeGuardedBatch(
                _singleExecution(
                    address(spoke),
                    abi.encodePacked(
                        abi.encodeWithSelector(spokeSelectors[i], RESERVE_ID, 1, smartAccount),
                        uint256(0)
                    )
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        COMPOUND V3 NO-DEBT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a mock Comet on usdcToken and whitelist its supply and withdraw selectors
     * @dev Mirrors the live whitelist, which grants a Comet exactly these two selectors.
     */
    function _deployAndWhitelistComet() internal returns (MockComet comet) {
        comet = new MockComet(address(usdcToken));
        vm.label(address(comet), "MockComet");

        address[] memory whitelistTargets = new address[](2);
        bytes4[] memory whitelistSelectors = new bytes4[](2);
        whitelistTargets[0] = address(comet);
        whitelistSelectors[0] = MockComet.supply.selector;
        whitelistTargets[1] = address(comet);
        whitelistSelectors[1] = MockComet.withdraw.selector;

        vm.prank(registryOwner);
        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
    }

    /**
     * @notice Test: a session key supplying collateral and borrowing the base asset reverts, and
     *         the whole batch rolls back
     * @dev This is the finding this check exists for. Comet's `withdraw` doubles as its borrow
     *      entrypoint, so on the whitelist alone a session key could pledge the Safe's WETH and
     *      borrow USDC to Comet's limit, a few percent above the liquidation threshold, then wait
     *      for a permissionless `absorb` to take the collateral minus the liquidation penalty.
     */
    function test_CometCollateralBorrowRevertsWholeBatch() public {
        MockComet comet = _deployAndWhitelistComet();

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(comet),
            value: 0,
            callData: abi.encodeCall(MockComet.supply, (address(wethToken), 10e18))
        });
        executions[1] = Execution({
            target: address(comet),
            value: 0,
            callData: abi.encodeCall(MockComet.withdraw, (address(usdcToken), 9e18))
        });

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.CometDebtNotAllowed.selector, address(comet), 9e18
            )
        );
        guardedModule.executeGuardedBatch(executions);

        assertEq(comet.debt(smartAccount), 0, "borrow rolled back");
        assertEq(comet.collateral(smartAccount), 0, "collateral supply rolled back");
    }

    /**
     * @notice Test: withdrawing no more than the supplied base balance is the lending exit and
     *         still passes
     */
    function test_CometWithdrawWithinSuppliedBalanceSucceeds() public {
        MockComet comet = _deployAndWhitelistComet();
        comet.setPosition(smartAccount, 1000e6, 0, 0);

        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                _singleExecution(
                    address(comet),
                    abi.encodeCall(MockComet.withdraw, (address(usdcToken), 1000e6))
                )
            )
        });

        assertEq(comet.baseBalance(smartAccount), 0, "position exited");
        assertEq(comet.debt(smartAccount), 0, "exit left no debt");
    }

    /**
     * @notice Test: a batch that only supplies is not debt-checked
     * @dev `supply` cannot create debt, so it is not checked. This keeps the check off every
     *      other venue that shares the `supply(address,uint256)` selector.
     */
    function test_CometSupplyOnlyBatchSkipsDebtCheck() public {
        MockComet comet = _deployAndWhitelistComet();

        vm.expectCall(address(comet), abi.encodeCall(MockComet.borrowBalanceOf, (smartAccount)), 0);
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                _singleExecution(
                    address(comet), abi.encodeCall(MockComet.supply, (address(usdcToken), 500e6))
                )
            )
        });

        assertEq(comet.baseBalance(smartAccount), 500e6, "supply executed");
    }

    /**
     * @notice Test: a pre-existing borrow can still be unwound — repay, then withdraw the freed
     *         collateral in the same batch
     * @dev The check reads the final position, so it does not trap an account that already owes
     *      on a Comet, whether the owner opened that debt directly or it predates this check.
     */
    function test_CometRepayAndCollateralWithdrawUnwindsExistingDebt() public {
        MockComet comet = _deployAndWhitelistComet();
        comet.setPosition(smartAccount, 0, 400e6, 10e18);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(comet),
            value: 0,
            callData: abi.encodeCall(MockComet.supply, (address(usdcToken), 400e6))
        });
        executions[1] = Execution({
            target: address(comet),
            value: 0,
            callData: abi.encodeCall(MockComet.withdraw, (address(wethToken), 10e18))
        });

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(executions);

        assertEq(comet.debt(smartAccount), 0, "debt repaid");
        assertEq(comet.collateral(smartAccount), 0, "collateral released");
    }

    /**
     * @notice Test: the debt check runs on every Comet a batch withdraws from
     */
    function test_CometDebtCheckedOnEveryComet() public {
        MockComet lending = _deployAndWhitelistComet();
        MockComet borrowing = _deployAndWhitelistComet();
        lending.setPosition(smartAccount, 1000e6, 0, 0);
        borrowing.setPosition(smartAccount, 0, 0, 10e18);

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(lending),
            value: 0,
            callData: abi.encodeCall(MockComet.withdraw, (address(usdcToken), 1000e6))
        });
        executions[1] = Execution({
            target: address(borrowing),
            value: 0,
            callData: abi.encodeCall(MockComet.withdraw, (address(usdcToken), 5e18))
        });

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.CometDebtNotAllowed.selector, address(borrowing), 5e18
            )
        );
        guardedModule.executeGuardedBatch(executions);

        assertEq(lending.baseBalance(smartAccount), 1000e6, "first withdraw rolled back");
    }

    /*//////////////////////////////////////////////////////////////
                    IPOR WITHDRAW MANAGER REQUEST FEE
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant VAULT_SHARES = 100e18;

    /**
     * @notice Deploy a mock IPOR WithdrawManager, whitelist requestShares on it and give the
     *         smart account VAULT_SHARES vault shares
     */
    function _deployAndWhitelistWithdrawManager(uint256 fee)
        internal
        returns (MockIporWithdrawManager wm, MockPlasmaVaultShares shares)
    {
        wm = new MockIporWithdrawManager();
        vm.label(address(wm), "MockIporWithdrawManager");
        wm.updateRequestFee(fee);
        shares = wm.plasmaVault();
        shares.mint(smartAccount, VAULT_SHARES);

        vm.startPrank(registryOwner);
        address[] memory whitelistTargets = new address[](1);
        bytes4[] memory whitelistSelectors = new bytes4[](1);
        whitelistTargets[0] = address(wm);
        whitelistSelectors[0] = MockIporWithdrawManager.requestShares.selector;
        registry.addToWhitelist(whitelistTargets, whitelistSelectors);
        vm.stopPrank();
    }

    function _requestSharesCall(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeCall(MockIporWithdrawManager.requestShares, (amount));
    }

    function _requestTwice(address first, address second, uint256 amount)
        internal
        pure
        returns (Execution[] memory executions)
    {
        executions = new Execution[](2);
        executions[0] = Execution({ target: first, value: 0, callData: _requestSharesCall(amount) });
        executions[1] = Execution({ target: second, value: 0, callData: _requestSharesCall(amount) });
    }

    /**
     * @notice Test: at fee 0 requestShares is unrestricted and takes no shares
     */
    function test_RequestSharesWithZeroFeeSucceeds() public {
        (MockIporWithdrawManager wm, MockPlasmaVaultShares shares) =
            _deployAndWhitelistWithdrawManager(0);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(wm), _requestSharesCall(VAULT_SHARES))
        );
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(_requestTwice(address(wm), address(wm), VAULT_SHARES));

        assertEq(wm.requestedShares(smartAccount), VAULT_SHARES, "request recorded");
        assertEq(shares.balanceOf(smartAccount), VAULT_SHARES, "no fee taken");
    }

    /**
     * @notice Test: with a fee, a request up to the balance passes and pays the fee once
     */
    function test_RequestSharesWithFeeWithinBalanceSucceeds() public {
        uint256 fee = 0.002e18;
        (MockIporWithdrawManager wm, MockPlasmaVaultShares shares) =
            _deployAndWhitelistWithdrawManager(fee);

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(wm), _requestSharesCall(VAULT_SHARES))
        );

        uint256 feeAmount = VAULT_SHARES * fee / 1e18;
        assertEq(wm.requestedShares(smartAccount), VAULT_SHARES - feeAmount, "request net of fee");
        assertEq(shares.balanceOf(smartAccount), VAULT_SHARES - feeAmount, "fee paid once");
    }

    /**
     * @notice Test: auditor scenario. With a 1% fee, requestShares(balance * 1e18 / fee) would
     *         take the whole balance as fee; the module rejects it and the shares stay put.
     */
    function test_RequestSharesAboveBalanceRevertsAndKeepsShares() public {
        uint256 fee = 0.01e18;
        (MockIporWithdrawManager wm, MockPlasmaVaultShares shares) =
            _deployAndWhitelistWithdrawManager(fee);
        uint256 drainAmount = VAULT_SHARES * 1e18 / fee;

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.RequestExceedsBalance.selector,
                address(wm),
                drainAmount,
                VAULT_SHARES
            )
        );
        guardedModule.executeGuardedBatch(
            _singleExecution(address(wm), _requestSharesCall(drainAmount))
        );

        assertEq(shares.balanceOf(smartAccount), VAULT_SHARES, "shares untouched");
        assertEq(wm.requestedShares(smartAccount), 0, "no request recorded");

        // The same call made directly by the account does burn the whole position
        vm.prank(smartAccount);
        wm.requestShares(drainAmount);
        assertEq(shares.balanceOf(smartAccount), 0, "direct call drains the position");
    }

    /**
     * @notice Test: with a fee, a request cannot replace one whose window is still open; it can
     *         once the window has passed or the request was redeemed
     */
    function test_RequestSharesWithFeeOnePerWindow() public {
        (MockIporWithdrawManager wm,) = _deployAndWhitelistWithdrawManager(0.01e18);
        Execution[] memory request = _singleExecution(address(wm), _requestSharesCall(1e18));

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(request);
        uint256 windowEnd = block.timestamp + wm.getWithdrawWindow();

        vm.warp(windowEnd);
        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.RequestAlreadyPending.selector, address(wm), windowEnd
            )
        );
        guardedModule.executeGuardedBatch(request);

        vm.warp(windowEnd + 1);
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(request);

        wm.clearRequest(smartAccount);
        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(request);
    }

    /**
     * @notice Test: with a fee, a batch cannot send two requests to the same WithdrawManager,
     *         but may send one to each of two WithdrawManagers
     */
    function test_RequestSharesWithFeeOnePerWithdrawManagerPerBatch() public {
        (MockIporWithdrawManager wm,) = _deployAndWhitelistWithdrawManager(0.01e18);
        (MockIporWithdrawManager otherWm, MockPlasmaVaultShares otherShares) =
            _deployAndWhitelistWithdrawManager(0.01e18);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.DuplicateRequest.selector, address(wm)
            )
        );
        guardedModule.executeGuardedBatch(_requestTwice(address(wm), address(wm), 1e18));

        vm.prank(smartAccount);
        guardedModule.executeGuardedBatch(_requestTwice(address(wm), address(otherWm), 1e18));
        assertGt(wm.requestedShares(smartAccount), 0, "first request");
        assertGt(otherWm.requestedShares(smartAccount), 0, "second request");
        assertLt(otherShares.balanceOf(smartAccount), VAULT_SHARES, "second fee paid");
    }

    /**
     * @notice Test: a request fee above MAX_REQUEST_FEE (1%) is rejected
     */
    function test_RequestSharesFeeAboveCapReverts() public {
        uint256 fee = 0.01e18 + 1;
        (MockIporWithdrawManager wm, MockPlasmaVaultShares shares) =
            _deployAndWhitelistWithdrawManager(fee);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.RequestFeeTooHigh.selector, address(wm), fee
            )
        );
        guardedModule.executeGuardedBatch(_singleExecution(address(wm), _requestSharesCall(1e18)));

        assertEq(shares.balanceOf(smartAccount), VAULT_SHARES, "shares untouched");
    }

    /**
     * @notice Test: with a fee, a withdraw window shorter than 1 day is rejected, so a session
     *         key cannot repeat requests faster than once a day
     */
    function test_RequestSharesWithFeeShortWindowReverts() public {
        (MockIporWithdrawManager wm, MockPlasmaVaultShares shares) =
            _deployAndWhitelistWithdrawManager(0.01e18);
        wm.updateWithdrawWindow(1 days - 1);

        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.WithdrawWindowTooShort.selector,
                address(wm),
                1 days - 1
            )
        );
        guardedModule.executeGuardedBatch(_singleExecution(address(wm), _requestSharesCall(1e18)));

        assertEq(shares.balanceOf(smartAccount), VAULT_SHARES, "shares untouched");
    }

    /**
     * @notice Test: requestShares calldata must be exactly selector + one word
     */
    function test_RequestSharesInvalidCalldataReverts() public {
        (MockIporWithdrawManager wm,) = _deployAndWhitelistWithdrawManager(0);

        vm.prank(smartAccount);
        vm.expectRevert(GuardedExecModuleUpgradeable.InvalidCalldata.selector);
        guardedModule.executeGuardedBatch(
            _singleExecution(address(wm), abi.encodePacked(_requestSharesCall(1e18), uint256(0)))
        );
    }

    /**
     * @notice Fuzz: whatever amounts a session key requests within one window, with any fee up
     *         to the cap the smart account loses at most fee * balance
     */
    function testFuzz_RequestSharesLossBoundedPerWindow(
        uint256 fee,
        uint256[5] memory amounts
    )
        public
    {
        fee = bound(fee, 1, 0.01e18);
        (MockIporWithdrawManager wm, MockPlasmaVaultShares shares) =
            _deployAndWhitelistWithdrawManager(fee);

        for (uint256 i = 0; i < amounts.length; i++) {
            Execution[] memory request =
                _singleExecution(address(wm), _requestSharesCall(bound(amounts[i], 1, type(uint128).max)));
            vm.prank(smartAccount);
            try guardedModule.executeGuardedBatch(request) { } catch { }
        }

        assertGe(
            shares.balanceOf(smartAccount),
            VAULT_SHARES - VAULT_SHARES * fee / 1e18,
            "loss above fee * balance"
        );
    }
}
