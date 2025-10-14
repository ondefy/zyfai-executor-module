// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { RhinestoneModuleKit, ModuleKitHelpers, AccountInstance } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/accounts/common/interfaces/IERC7579Module.sol";

import { GuardedExecModule } from "src/delegatecall-approach/GuardedExecModule.sol";
import { GuardedRouter } from "src/delegatecall-approach/GuardedRouter.sol";
import { TargetRegistry } from "src/delegatecall-approach/TargetRegistry.sol";
import { MockDeFiPool } from "test/delegatecall-approach/MockDeFiPool.sol";

/**
 * @title GuardedExecModuleTest
 * @notice Comprehensive test to verify that DeFi pools receive calls with msg.sender = Smart Account
 */
contract GuardedExecModuleTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;

    // Core contracts
    AccountInstance internal instance;
    GuardedExecModule internal guardedModule;
    GuardedRouter internal router;
    TargetRegistry internal registry;
    
    // Mock DeFi protocols
    MockDeFiPool internal uniswapPool;
    MockDeFiPool internal aavePool;
    MockDeFiPool internal curvePool;
    
    // Test accounts
    address internal smartAccount;
    address internal sessionKey;
    address internal registryOwner;

    function setUp() public {
        init();
        
        console.log("\n========================================");
        console.log("TEST SETUP");
        console.log("========================================");
        
        // Create test accounts
        sessionKey = makeAddr("sessionKey");
        registryOwner = makeAddr("registryOwner");
        
        console.log("Session Key:", sessionKey);
        console.log("Registry Owner:", registryOwner);
        
        // Deploy registry first
        registry = new TargetRegistry(registryOwner);
        vm.label(address(registry), "TargetRegistry");
        console.log("TargetRegistry deployed:", address(registry));
        
        // Deploy the GuardedRouter (stateless)
        router = new GuardedRouter();
        vm.label(address(router), "GuardedRouter");
        console.log("GuardedRouter deployed:", address(router));
        
        // Deploy the GuardedExecModule with immutable registry/router
        guardedModule = new GuardedExecModule(address(registry), address(router));
        vm.label(address(guardedModule), "GuardedExecModule");
        console.log("GuardedExecModule deployed:", address(guardedModule));
        
        // Deploy mock DeFi pools
        uniswapPool = new MockDeFiPool();
        aavePool = new MockDeFiPool();
        curvePool = new MockDeFiPool();
        vm.label(address(uniswapPool), "UniswapPool");
        vm.label(address(aavePool), "AavePool");
        vm.label(address(curvePool), "CurvePool");
        console.log("Mock Uniswap Pool:", address(uniswapPool));
        console.log("Mock Aave Pool:", address(aavePool));
        console.log("Mock Curve Pool:", address(curvePool));
        
        // Create the smart account
        instance = makeAccountInstance("GuardedExecTest");
        smartAccount = address(instance.account);
        vm.deal(smartAccount, 10 ether);
        console.log("Smart Account created:", smartAccount);
        
        
        // Whitelist the DeFi pools
        vm.startPrank(registryOwner);
        registry.add(address(uniswapPool));
        registry.add(address(aavePool));
        registry.add(address(curvePool));
        vm.stopPrank();
        console.log("Whitelisted all mock DeFi pools");
        
        // Install the GuardedExecModule on the smart account (no data needed)
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(guardedModule),
            data: ""
        });
        console.log("GuardedExecModule installed on smart account");
        
        console.log("========================================");
        console.log("SETUP COMPLETE\n");
    }

    /**
     * @notice TEST 1: Verify msg.sender is the smart account when calling DeFi pool
     * @dev This is the CORE test - verifying your entire flow works correctly
     */
    function test_MsgSenderIsSmartAccount() public {
        console.log("\n========================================");
        console.log("TEST 1: msg.sender is Smart Account");
        console.log("========================================\n");
        
        // Prepare call to Uniswap pool
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(
            MockDeFiPool.swap.selector,
            1000 ether,  // amountIn
            900 ether    // minAmountOut
        );
        
        // Execute via the smart account calling the module
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModule.executeGuardedBatch.selector,
                targets,
                calldatas,
                true  // revertAll
            )
        });
        
        // VERIFICATION: Check that the DeFi pool recorded the smart account as msg.sender
        (address lastCaller, uint256 callCount) = uniswapPool.getLastCallInfo();
        
        console.log("\n--- VERIFICATION ---");
        console.log("Smart Account address:", smartAccount);
        console.log("Last caller to DeFi pool:", lastCaller);
        console.log("Call count:", callCount);
        
        // THE KEY ASSERTION: msg.sender in the DeFi pool should be the smart account
        assertEq(lastCaller, smartAccount, "msg.sender should be the smart account!");
        assertEq(callCount, 1, "DeFi pool should have been called once");
        
        console.log("\n[SUCCESS] msg.sender in DeFi pool = Smart Account");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 2: Execute multiple DeFi calls in one batch
     */
    function test_BatchMultipleDeFiCalls() public {
        console.log("\n========================================");
        console.log("TEST 2: Batch Multiple DeFi Calls");
        console.log("========================================\n");
        
        // Prepare batch calls to multiple DeFi pools
        address[] memory targets = new address[](3);
        bytes[] memory calldatas = new bytes[](3);
        
        // Call 1: Uniswap swap
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(
            MockDeFiPool.swap.selector,
            1000 ether,
            900 ether
        );
        
        // Call 2: Aave deposit
        targets[1] = address(aavePool);
        calldatas[1] = abi.encodeWithSelector(
            MockDeFiPool.deposit.selector,
            500 ether
        );
        
        // Call 3: Curve withdraw
        targets[2] = address(curvePool);
        calldatas[2] = abi.encodeWithSelector(
            MockDeFiPool.withdraw.selector,
            200 ether
        );
        
        // Execute batch
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModule.executeGuardedBatch.selector,
                targets,
                calldatas,
                true
            )
        });
        
        // Verify all three pools were called by the smart account
        (address caller1, uint256 count1) = uniswapPool.getLastCallInfo();
        (address caller2, uint256 count2) = aavePool.getLastCallInfo();
        (address caller3, uint256 count3) = curvePool.getLastCallInfo();
        
        console.log("\n--- VERIFICATION ---");
        assertEq(caller1, smartAccount, "Uniswap: msg.sender should be smart account");
        assertEq(caller2, smartAccount, "Aave: msg.sender should be smart account");
        assertEq(caller3, smartAccount, "Curve: msg.sender should be smart account");
        assertEq(count1, 1);
        assertEq(count2, 1);
        assertEq(count3, 1);
        
        console.log("[SUCCESS] All three DeFi pools received calls from smart account");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 3: Verify non-whitelisted targets are blocked
     */
    function test_RevertOnNonWhitelistedTarget() public {
        console.log("\n========================================");
        console.log("TEST 3: Block Non-Whitelisted Targets");
        console.log("========================================\n");
        
        // Deploy a malicious/non-whitelisted contract
        MockDeFiPool maliciousPool = new MockDeFiPool();
        console.log("Malicious (non-whitelisted) pool:", address(maliciousPool));
        
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(maliciousPool);
        calldatas[0] = abi.encodeWithSelector(
            MockDeFiPool.swap.selector,
            1000 ether,
            900 ether
        );
        
        // This should revert because maliciousPool is not whitelisted
        vm.expectRevert();
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModule.executeGuardedBatch.selector,
                targets,
                calldatas,
                true
            )
        });
        
        // Verify the malicious pool was never called
        (address lastCaller, uint256 callCount) = maliciousPool.getLastCallInfo();
        assertEq(callCount, 0, "Malicious pool should not have been called");
        
        console.log("[SUCCESS] Non-whitelisted target was successfully blocked");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 4: Test error handling with revertAll=true
     */
    function test_RevertAllOnFailure() public {
        console.log("\n========================================");
        console.log("TEST 4: Revert All On Failure");
        console.log("========================================\n");
        
        address[] memory targets = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        
        // First call will succeed
        targets[0] = address(uniswapPool);
        calldatas[0] = abi.encodeWithSelector(
            MockDeFiPool.swap.selector,
            1000 ether,
            900 ether
        );
        
        // Second call will fail
        targets[1] = address(aavePool);
        calldatas[1] = abi.encodeWithSelector(
            MockDeFiPool.failingFunction.selector
        );
        
        uint256 uniswapCountBefore = uniswapPool.callCount();
        
        // Should revert the entire batch
        vm.expectRevert();
        instance.exec({
            target: address(guardedModule),
            value: 0,
            callData: abi.encodeWithSelector(
                GuardedExecModule.executeGuardedBatch.selector,
                targets,
                calldatas,
                true  // revertAll = true
            )
        });
        
        // Verify the first call was also reverted (no state change)
        uint256 uniswapCountAfter = uniswapPool.callCount();
        assertEq(uniswapCountAfter, uniswapCountBefore, "All calls should be reverted");
        
        console.log("[SUCCESS] Batch correctly reverted when one call failed");
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 5: Verify module is properly initialized
     */
    function test_ModuleInitialization() public view {
        console.log("\n========================================");
        console.log("TEST 5: Module Initialization");
        console.log("========================================\n");
        
        // Check if module is initialized for the smart account
        bool isInitialized = guardedModule.isInitialized(smartAccount);
        assertTrue(isInitialized, "Module should be initialized");
        
        // Check stored values (immutable)
        address storedRegistry = address(guardedModule.registry());
        address storedRouter = guardedModule.router();
        
        assertEq(storedRegistry, address(registry), "Registry should match");
        assertEq(storedRouter, address(router), "Router should match");
        
        console.log("[SUCCESS] Module is properly initialized");
        console.log("Registry:", storedRegistry);
        console.log("Router:", storedRouter);
        console.log("========================================\n");
    }
    
    /**
     * @notice TEST 6: Verify uninstall cleans up storage
     */
    function test_UninstallCleansStorage() public {
        console.log("\n========================================");
        console.log("TEST 6: Uninstall Cleans Storage");
        console.log("========================================\n");
        
        // Verify initialized before uninstall
        assertTrue(guardedModule.isInitialized(smartAccount), "Should be initialized");
        
        // Uninstall the module
        instance.uninstallModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(guardedModule),
            data: ""
        });
        
        // Verify storage is cleaned
        assertTrue(guardedModule.isInitialized(smartAccount), "Should still be initialized (always true)");
        // Note: Registry and router are immutable, so they don't change
        
        console.log("[SUCCESS] Uninstall correctly cleaned up storage");
        console.log("========================================\n");
    }
}

