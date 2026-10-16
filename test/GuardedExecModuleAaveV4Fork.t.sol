// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { RhinestoneModuleKit, ModuleKitHelpers, AccountInstance } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/accounts/common/interfaces/IERC7579Module.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TargetRegistry } from "src/registry/TargetRegistry.sol";
import { GuardedExecModuleUpgradeable } from "src/module/GuardedExecModuleUpgradeable.sol";
import { IAaveV4Spoke } from "src/interfaces/IAaveV4Spoke.sol";

/**
 * @title GuardedExecModuleAaveV4ForkTest
 * @notice Mainnet fork test of the minimum health factor check against the live Aave v4 Main
 *         Spoke. Skipped unless MAINNET_RPC_URL is set.
 */
contract GuardedExecModuleAaveV4ForkTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;

    address internal constant MAIN_SPOKE = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 internal constant WETH_RESERVE_ID = 0;
    uint256 internal constant USDC_RESERVE_ID = 7;
    uint256 internal constant FORK_BLOCK = 26_204_763;

    bytes4 internal constant SUPPLY = bytes4(keccak256("supply(uint256,uint256,address)"));
    bytes4 internal constant WITHDRAW = bytes4(keccak256("withdraw(uint256,uint256,address)"));
    bytes4 internal constant BORROW = bytes4(keccak256("borrow(uint256,uint256,address)"));
    bytes4 internal constant SET_COLLATERAL =
        bytes4(keccak256("setUsingAsCollateral(uint256,bool,address)"));

    AccountInstance internal instance;
    GuardedExecModuleUpgradeable internal guardedModule;
    address internal account;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
        init();

        address owner = makeAddr("owner");
        TargetRegistry registry = new TargetRegistry(owner);
        address[] memory targets = new address[](5);
        bytes4[] memory selectors = new bytes4[](5);
        (targets[0], selectors[0]) = (WETH, IERC20.approve.selector);
        (targets[1], selectors[1]) = (MAIN_SPOKE, SUPPLY);
        (targets[2], selectors[2]) = (MAIN_SPOKE, WITHDRAW);
        (targets[3], selectors[3]) = (MAIN_SPOKE, BORROW);
        (targets[4], selectors[4]) = (MAIN_SPOKE, SET_COLLATERAL);
        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);

        GuardedExecModuleUpgradeable implementation = new GuardedExecModuleUpgradeable();
        guardedModule = GuardedExecModuleUpgradeable(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        GuardedExecModuleUpgradeable.initialize, (address(registry), owner)
                    )
                )
            )
        );

        instance = makeAccountInstance("AaveV4ForkAccount");
        account = address(instance.account);
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR, module: address(guardedModule), data: ""
        });

        deal(WETH, account, 10 ether);
        Execution[] memory executions = new Execution[](3);
        executions[0] = _exec(WETH, abi.encodeCall(IERC20.approve, (MAIN_SPOKE, 10 ether)));
        executions[1] = _exec(MAIN_SPOKE, _spokeCall(SUPPLY, WETH_RESERVE_ID, 10 ether));
        executions[2] = _exec(
            MAIN_SPOKE, abi.encodeWithSelector(SET_COLLATERAL, WETH_RESERVE_ID, true, account)
        );
        vm.prank(account);
        guardedModule.executeGuardedBatch(executions);
    }

    /**
     * @notice Test: against the real Spoke, borrow and withdraw are capped at health factor 1.5
     *         even though the Spoke itself would accept them down to 1.0
     */
    function test_Fork_MainSpokeEnforcesMinHealthFactor() public {
        // Probe: borrow 1,000 USDC to learn the health factor per unit of debt
        _batch(_exec(MAIN_SPOKE, _spokeCall(BORROW, USDC_RESERVE_ID, 1000e6)));
        uint256 probeHf = _healthFactor();
        assertGt(probeHf, 1.5e18, "probe borrow is far from the limit");

        // Health factor is inversely proportional to debt: debt at HF t = 1000e6 * probeHf / t
        uint256 debtAtHf1_3 = 1000e6 * probeHf / 1.3e18;
        uint256 debtAtHf1_8 = 1000e6 * probeHf / 1.8e18;

        // A borrow to HF ~1.3 is accepted by the Spoke but rejected by the module
        vm.prank(account);
        vm.expectPartialRevert(GuardedExecModuleUpgradeable.HealthFactorTooLow.selector);
        guardedModule.executeGuardedBatch(
            _single(_exec(MAIN_SPOKE, _spokeCall(BORROW, USDC_RESERVE_ID, debtAtHf1_3 - 1000e6)))
        );

        // A borrow to HF ~1.8 passes
        _batch(_exec(MAIN_SPOKE, _spokeCall(BORROW, USDC_RESERVE_ID, debtAtHf1_8 - 1000e6)));
        uint256 hf = _healthFactor();
        assertGe(hf, 1.5e18, "health factor stays above the minimum");

        // Withdrawing 25% of collateral would take HF to ~1.35: rejected
        vm.prank(account);
        vm.expectPartialRevert(GuardedExecModuleUpgradeable.HealthFactorTooLow.selector);
        guardedModule.executeGuardedBatch(
            _single(_exec(MAIN_SPOKE, _spokeCall(WITHDRAW, WETH_RESERVE_ID, 2.5 ether)))
        );
        assertEq(_healthFactor(), hf, "rejected withdraw left the position unchanged");
    }

    function _healthFactor() internal view returns (uint256) {
        return IAaveV4Spoke(MAIN_SPOKE).getUserAccountData(account).healthFactor;
    }

    function _spokeCall(
        bytes4 selector,
        uint256 reserveId,
        uint256 amount
    )
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeWithSelector(selector, reserveId, amount, account);
    }

    function _exec(address target, bytes memory callData) internal pure returns (Execution memory) {
        return Execution({ target: target, value: 0, callData: callData });
    }

    function _single(Execution memory execution) internal pure returns (Execution[] memory e) {
        e = new Execution[](1);
        e[0] = execution;
    }

    function _batch(Execution memory execution) internal {
        vm.prank(account);
        guardedModule.executeGuardedBatch(_single(execution));
    }
}
