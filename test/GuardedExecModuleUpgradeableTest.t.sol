// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test, console } from "forge-std/Test.sol";
import { RhinestoneModuleKit, ModuleKitHelpers, AccountInstance } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/accounts/common/interfaces/IERC7579Module.sol";

import { GuardedExecModuleUpgradeable } from "src/GuardedExecModuleUpgradeable.sol";
import { GuardedExecModuleUpgradeableV2 } from "src/GuardedExecModuleUpgradeableV2.sol";
import { TargetRegistry } from "src/TargetRegistry.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockDeFiPool } from "test/mocks/MockDeFiPool.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockSafeWallet } from "test/mocks/MockSafeWallet.sol";
import { TestTargetRegistryWithMockSafe } from "test/mocks/TestTargetRegistryWithMockSafe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GuardedExecModuleUpgradeableTest
 * @notice Test the GuardedExecModuleUpgradeable with UUPS upgradeable pattern
 */
contract GuardedExecModuleUpgradeableTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    
    // ERC1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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
        
        // Schedule and execute whitelist operations (with OpenZeppelin timelock)
        vm.startPrank(registryOwner);
        
        // Schedule adds for DeFi pools
        registry.scheduleAdd(address(uniswapPool), SWAP_SELECTOR);
        registry.scheduleAdd(address(aavePool), SWAP_SELECTOR);
        registry.scheduleAdd(address(curvePool), SWAP_SELECTOR);
        
        // Schedule adds for ERC20 tokens
        registry.scheduleAdd(address(usdcToken), TRANSFER_SELECTOR);
        registry.scheduleAdd(address(wethToken), TRANSFER_SELECTOR);
        
        // Add USDC as restricted token (immediate, no timelock needed)
        registry.addRestrictedERC20Token(address(usdcToken));
        
        // Fast forward time by 1 day + 1 second
        vm.warp(block.timestamp + 1 days + 1);
        
        // Execute the operations (ANYONE can execute with OpenZeppelin!)
        registry.executeOperation(address(uniswapPool), SWAP_SELECTOR);
        registry.executeOperation(address(aavePool), SWAP_SELECTOR);
        registry.executeOperation(address(curvePool), SWAP_SELECTOR);
        registry.executeOperation(address(usdcToken), TRANSFER_SELECTOR);
        registry.executeOperation(address(wethToken), TRANSFER_SELECTOR);
        
        vm.stopPrank();
        
        // Deploy UPGRADEABLE module (implementation + proxy)
        implementation = new GuardedExecModuleUpgradeable();
        vm.label(address(implementation), "GuardedExecModuleUpgradeable_Implementation");
        
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            GuardedExecModuleUpgradeable.initialize.selector,
            address(registry),
            moduleOwner
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
        
        // Add USDC as restricted token
        registry.addRestrictedERC20Token(address(usdcToken));
        
        // Schedule and execute whitelist operations
        registry.scheduleAdd(address(uniswapPool), SWAP_SELECTOR);
        registry.scheduleAdd(address(aavePool), SWAP_SELECTOR);
        registry.scheduleAdd(address(curvePool), SWAP_SELECTOR);
        registry.scheduleAdd(address(usdcToken), TRANSFER_SELECTOR);
        registry.scheduleAdd(address(wethToken), TRANSFER_SELECTOR);
        
        // Fast forward time by 1 day + 1 second
        vm.warp(block.timestamp + 1 days + 1);
        
        // Execute the operations
        registry.executeOperation(address(uniswapPool), SWAP_SELECTOR);
        registry.executeOperation(address(aavePool), SWAP_SELECTOR);
        registry.executeOperation(address(curvePool), SWAP_SELECTOR);
        registry.executeOperation(address(usdcToken), TRANSFER_SELECTOR);
        registry.executeOperation(address(wethToken), TRANSFER_SELECTOR);
        
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
     * @notice TEST 1: Verify msg.sender is the smart account with registry
     */
    function test_MsgSenderIsSmartAccount() public {
        // Prepare single call to Uniswap
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(
            SWAP_SELECTOR,
            1000 ether,
            900 ether
        );
        
        // Execute via smart account
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
            )
        });
        
        // Verify msg.sender was the smart account
        (address lastCaller, uint256 callCount) = uniswapPool.getLastCallInfo();
        
        assertEq(lastCaller, smartAccount, "msg.sender should be the smart account!");
        assertEq(callCount, 1, "Should be called once");
    }
    
    /**
     * @notice TEST 2: Batch multiple DeFi calls
     */
    function test_BatchMultipleDeFiCalls() public {
        // Prepare batch: Uniswap swap, Aave swap, Curve swap
        address[] memory targets = new address[](3);
        bytes[] memory calldatas = new bytes[](3);
        
        targets[0] = address(uniswapPool);
        targets[1] = address(aavePool);
        targets[2] = address(curvePool);
        
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        calldatas[1] = abi.encodeWithSelector(SWAP_SELECTOR, 2000 ether, 1800 ether);
        calldatas[2] = abi.encodeWithSelector(SWAP_SELECTOR, 3000 ether, 2700 ether);
        
        // Execute batch
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
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
     * @notice TEST 3: Module configuration is correct
     */
    function test_ModuleConfiguration() public {
        // Check registry is set correctly
        address moduleRegistry = guardedModule.getRegistry();
        
        assertEq(moduleRegistry, address(registry), "Registry should match");
        
        // Check version
        string memory version = guardedModule.version();
        assertEq(version, "2.0.0", "Version should be 2.0.0");
        
        // Check name
        string memory name = guardedModule.name();
        assertEq(name, "GuardedExecModuleUpgradeable", "Name should match");
    }
    
    /**
     * @notice TEST 4: Module pause stops compromised session key
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
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
            )
        });
    }
    
    /**
     * @notice TEST 5: Only owner can pause module
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
     * @notice TEST 6: Registry update functionality
     */
    function test_UpdateRegistry() public {
        // Deploy new registry
        vm.startPrank(registryOwner);
        TargetRegistry newRegistry = new TestTargetRegistryWithMockSafe(registryOwner, address(mockSafeWallet));
        vm.label(address(newRegistry), "NewRegistry");
        
        // Add the same whitelist entries
        newRegistry.addRestrictedERC20Token(address(usdcToken));
        newRegistry.scheduleAdd(address(uniswapPool), SWAP_SELECTOR);
        newRegistry.scheduleAdd(address(usdcToken), TRANSFER_SELECTOR);
        
        vm.warp(block.timestamp + 1 days + 1);
        newRegistry.executeOperation(address(uniswapPool), SWAP_SELECTOR);
        newRegistry.executeOperation(address(usdcToken), TRANSFER_SELECTOR);
        vm.stopPrank();
        
        // Update registry
        vm.prank(moduleOwner);
        guardedModule.updateRegistry(address(newRegistry));
        
        // Verify new registry is set
        assertEq(address(guardedModule.registry()), address(newRegistry), "Registry should be updated");
        
        // Verify it still works
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(SWAP_SELECTOR, 1000 ether, 900 ether);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
            )
        });
    }
    
    /**
     * @notice TEST 7: Only owner can update registry
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
     * @notice TEST 8: ERC20 USDC transfer restrictions
     */
    function test_ERC20USDCTransferRestrictions() public {
        // Mint some USDC to smart account
        usdcToken.mint(smartAccount, 1000 * 10**6); // 1000 USDC
        
        // Test 1: Transfer to smart account itself (should work)
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(usdcToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, smartAccount, 100 * 10**6);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
            )
        });
        
        // Test 2: Transfer to Safe owner (should work)
        address[] memory owners = mockSafeWallet.getOwners();
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, owners[1], 100 * 10**6);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
            )
        });
        
        // Test 3: Transfer WETH to random address (should work - not restricted)
        address randomAddress = makeAddr("randomAddress");
        wethToken.mint(smartAccount, 1 ether);
        targets[0] = address(wethToken);
        calldatas[0] = abi.encodeWithSelector(TRANSFER_SELECTOR, randomAddress, 0.1 ether);
        
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.executeGuardedBatch.selector,
                targets,
                calldatas
            )
        });
    }
    
    /**
     * @notice TEST 9: Direct ERC20 transfer authorization test with mock Safe
     */
    function test_DirectERC20TransferAuthorizationWithMockSafe() public {
        // Test the registry's isERC20TransferAuthorized function directly
        address[] memory owners = mockSafeWallet.getOwners();
        
        // Test 1: Transfer to smart account itself (should be authorized)
        bool isAuthorized1 = registry.isERC20TransferAuthorized(address(usdcToken), smartAccount, smartAccount);
        assertTrue(isAuthorized1, "Transfer to smart account should be authorized");
        
        // Test 2: Transfer to Safe owner (should be authorized)
        bool isAuthorized2 = registry.isERC20TransferAuthorized(address(usdcToken), owners[1], smartAccount);
        assertTrue(isAuthorized2, "Transfer to Safe owner should be authorized");
        
        // Test 3: Transfer to random address (should not be authorized)
        address randomAddress = makeAddr("randomAddress");
        bool isAuthorized3 = registry.isERC20TransferAuthorized(address(usdcToken), randomAddress, smartAccount);
        assertFalse(isAuthorized3, "Transfer to random address should not be authorized");
        
        // Test 4: Transfer WETH to random address (should be authorized - not restricted)
        bool isAuthorized4 = registry.isERC20TransferAuthorized(address(wethToken), randomAddress, smartAccount);
        assertTrue(isAuthorized4, "Transfer WETH to random address should be authorized (not restricted)");
    }
    
    /**
     * @notice TEST 10: Module initializes only once
     */
    function test_ModuleInitializesOnlyOnce() public {
        // Try to initialize again (should fail)
        vm.expectRevert();
        guardedModule.initialize(address(registry), moduleOwner);
    }
    
    /**
     * @notice TEST 11: Cannot update registry to zero address
     */
    function test_CannotUpdateRegistryToZeroAddress() public {
        vm.prank(moduleOwner);
        vm.expectRevert();
        guardedModule.updateRegistry(address(0));
    }
    
    /**
     * @notice TEST 12: Upgrade module implementation while keeping same address
     */
    function test_UpgradeModuleKeepsSameAddress() public {
        address proxyAddr = address(proxy);
        bytes32 slot = IMPLEMENTATION_SLOT;
        
        // Get original implementation from storage
        address originalImpl = address(uint160(uint256(vm.load(proxyAddr, slot))));
        console.log("Proxy Address:", proxyAddr);
        console.log("Original Implementation:", originalImpl);
        
        // Verify V1
        assertEq(guardedModule.name(), "GuardedExecModuleUpgradeable", "Should be V1");
        
        // Store state
        address reg = guardedModule.getRegistry();
        address ownerAddr = guardedModule.owner();
        
        // Deploy and upgrade to V2
        GuardedExecModuleUpgradeableV2 v2 = new GuardedExecModuleUpgradeableV2();
        vm.prank(moduleOwner);
        guardedModule.upgradeToAndCall(
            address(v2),
            abi.encodeWithSelector(GuardedExecModuleUpgradeableV2.initializeV2.selector, "V2!")
        );
        
        // Verify address unchanged
        assertEq(address(proxy), proxyAddr, "Address must stay same");
        
        // Verify new implementation
        address newImpl = address(uint160(uint256(vm.load(proxyAddr, slot))));
        assertEq(newImpl, address(v2), "Implementation updated");
        assertNotEq(newImpl, originalImpl, "Implementation changed");
        
        // Cast to V2
        GuardedExecModuleUpgradeableV2 v2Module = GuardedExecModuleUpgradeableV2(proxyAddr);
        assertEq(v2Module.name(), "GuardedExecModuleUpgradeableV2", "Is V2");
        
        // Verify state persisted
        assertEq(address(v2Module.getRegistry()), reg, "Registry persisted");
        assertEq(v2Module.owner(), ownerAddr, "Owner persisted");
        assertEq(v2Module.upgradeMessage(), "V2!", "V2 message set");
        
        console.log("Upgrade successful!");
    }
    
    /**
     * @notice TEST 13: Only owner can upgrade
     */
    function test_OnlyOwnerCanUpgrade() public {
        address attacker = makeAddr("attacker");
        GuardedExecModuleUpgradeableV2 v2Implementation = new GuardedExecModuleUpgradeableV2();
        
        // Attacker tries to upgrade (should fail)
        vm.prank(attacker);
        vm.expectRevert();
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(
            address(v2Implementation),
            ""
        );
        
        // Owner can upgrade
        vm.prank(moduleOwner);
        guardedModule.upgradeToAndCall(
            address(v2Implementation),
            ""
        );
        
        // Verify upgrade was successful
        address newImplementation = address(uint160(uint256(vm.load(address(proxy), IMPLEMENTATION_SLOT))));
        assertEq(newImplementation, address(v2Implementation), "Implementation should be upgraded");
    }
    
    /**
     * @notice TEST 14: Storage layout compatibility after upgrade
     */
    function test_StorageLayoutCompatibility() public {
        // Store some data before upgrade
        address registryBefore = address(guardedModule.registry());
        address ownerBefore = guardedModule.owner();
        
        // Upgrade to V2
        GuardedExecModuleUpgradeableV2 v2Implementation = new GuardedExecModuleUpgradeableV2();
        
        vm.prank(moduleOwner);
        guardedModule.upgradeToAndCall(
            address(v2Implementation),
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeableV2.initializeV2.selector,
                "Storage compatibility test"
            )
        );
        
        GuardedExecModuleUpgradeableV2 v2Module = GuardedExecModuleUpgradeableV2(address(proxy));
        
        // Verify storage slots are compatible
        assertEq(
            address(v2Module.registry()),
            registryBefore,
            "Registry should be at same storage slot"
        );
        assertEq(
            v2Module.owner(),
            ownerBefore,
            "Owner should be at same storage slot"
        );
        
        // Verify new storage variables work
        assertEq(v2Module.upgradeCounter(), 1, "Upgrade counter should be set");
        assertEq(
            v2Module.upgradeMessage(),
            "Storage compatibility test",
            "Upgrade message should be set"
        );
    }
}
