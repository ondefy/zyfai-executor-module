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

/// @notice Comet reads used by this test on top of the module's own `borrowBalanceOf`
interface ICometReads {
    function balanceOf(address account) external view returns (uint256);
    function collateralBalanceOf(address account, address asset) external view returns (uint128);
    function borrowBalanceOf(address account) external view returns (uint256);
}

/**
 * @title GuardedExecModuleCometForkTest
 * @notice Base fork test of the no-Comet-debt check against the live Compound V3 USDC market.
 *         Proves that Comet's `withdraw` doubles as a borrow and that the module now blocks it
 *         while leaving the lending path intact. Skipped unless BASE_RPC_URL is set.
 */
contract GuardedExecModuleCometForkTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;

    /// @notice Compound V3 USDC market on Base (`cUSDCv3`)
    address internal constant COMET = 0xb125E6687d4313864e53df431d5425969c15Eb2F;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    uint256 internal constant FORK_BLOCK = 52_900_000;

    uint256 internal constant COLLATERAL = 1 ether;
    uint256 internal constant BORROW = 500e6;
    uint256 internal constant LEND = 1000e6;

    bytes4 internal constant COMET_SUPPLY = bytes4(keccak256("supply(address,uint256)"));
    bytes4 internal constant COMET_WITHDRAW = bytes4(keccak256("withdraw(address,uint256)"));

    AccountInstance internal instance;
    GuardedExecModuleUpgradeable internal guardedModule;
    address internal account;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
        init();

        address owner = makeAddr("owner");
        TargetRegistry registry = new TargetRegistry(owner);
        address[] memory targets = new address[](4);
        bytes4[] memory selectors = new bytes4[](4);
        (targets[0], selectors[0]) = (USDC, IERC20.approve.selector);
        (targets[1], selectors[1]) = (WETH, IERC20.approve.selector);
        (targets[2], selectors[2]) = (COMET, COMET_SUPPLY);
        (targets[3], selectors[3]) = (COMET, COMET_WITHDRAW);
        vm.prank(owner);
        registry.addToWhitelist(targets, selectors);

        GuardedExecModuleUpgradeable implementation =
            new GuardedExecModuleUpgradeable(0xaffD3c3cD06cf499deddf78b26868018A93f2C31);
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

        instance = makeAccountInstance("CometForkAccount");
        account = address(instance.account);
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR, module: address(guardedModule), data: ""
        });

        deal(WETH, account, COLLATERAL);
        deal(USDC, account, LEND);
    }

    /**
     * @notice Test: against the real Comet, pledging collateral and withdrawing the base asset is
     *         an uncapped borrow, and the module reverts the whole batch
     */
    function test_Fork_CometCollateralBorrowReverts() public {
        Execution[] memory executions = new Execution[](3);
        executions[0] = _exec(WETH, abi.encodeCall(IERC20.approve, (COMET, COLLATERAL)));
        executions[1] = _exec(COMET, abi.encodeWithSelector(COMET_SUPPLY, WETH, COLLATERAL));
        executions[2] = _exec(COMET, abi.encodeWithSelector(COMET_WITHDRAW, USDC, BORROW));

        vm.prank(account);
        vm.expectPartialRevert(GuardedExecModuleUpgradeable.CometDebtNotAllowed.selector);
        guardedModule.executeGuardedBatch(executions);

        assertEq(ICometReads(COMET).borrowBalanceOf(account), 0, "no debt opened");
        assertEq(ICometReads(COMET).collateralBalanceOf(account, WETH), 0, "collateral rolled back");
        assertEq(IERC20(WETH).balanceOf(account), COLLATERAL, "WETH untouched");
    }

    /**
     * @notice Test: the lending path Zyfai actually uses — supply the base asset, then withdraw
     * it
     *         — still works under the check
     */
    function test_Fork_CometLendAndExitSucceeds() public {
        Execution[] memory executions = new Execution[](2);
        executions[0] = _exec(USDC, abi.encodeCall(IERC20.approve, (COMET, LEND)));
        executions[1] = _exec(COMET, abi.encodeWithSelector(COMET_SUPPLY, USDC, LEND));
        vm.prank(account);
        guardedModule.executeGuardedBatch(executions);

        // Exit the whole position, as zyfai-api does: it reads this balance off-chain and
        // withdraws exactly it. Comet rounds the supplied principal down, so asking for the
        // original amount would overdraw by dust, which Comet itself rejects as a borrow.
        uint256 supplied = ICometReads(COMET).balanceOf(account);
        assertApproxEqAbs(supplied, LEND, 1, "supplied to Comet");

        vm.prank(account);
        guardedModule.executeGuardedBatch(
            _single(_exec(COMET, abi.encodeWithSelector(COMET_WITHDRAW, USDC, supplied)))
        );

        assertEq(ICometReads(COMET).borrowBalanceOf(account), 0, "exit left no debt");
        assertEq(ICometReads(COMET).balanceOf(account), 0, "position fully exited");
        assertEq(IERC20(USDC).balanceOf(account), supplied, "USDC back in the account");
    }

    function _exec(address target, bytes memory callData) internal pure returns (Execution memory) {
        return Execution({ target: target, value: 0, callData: callData });
    }

    function _single(Execution memory execution) internal pure returns (Execution[] memory e) {
        e = new Execution[](1);
        e[0] = execution;
    }
}
