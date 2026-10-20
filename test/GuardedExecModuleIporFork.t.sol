// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { RhinestoneModuleKit, ModuleKitHelpers, AccountInstance } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/accounts/common/interfaces/IERC7579Module.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TargetRegistry } from "src/registry/TargetRegistry.sol";
import { GuardedExecModuleUpgradeable } from "src/module/GuardedExecModuleUpgradeable.sol";
import { IIporWithdrawManager } from "src/interfaces/IIporWithdrawManager.sol";

interface IIporAccessManager {
    function grantRole(uint64 roleId, address account, uint32 executionDelay) external;
}

interface IWithdrawManagerAdmin {
    struct WithdrawRequestInfo {
        uint256 shares;
        uint256 endWithdrawWindowTimestamp;
        bool canWithdraw;
        uint256 withdrawWindowInSeconds;
    }

    function requestShares(uint256 shares) external;
    function updateRequestFee(uint256 fee) external;
    function requestInfo(address account) external view returns (WithdrawRequestInfo memory);
}

/**
 * @title GuardedExecModuleIporForkTest
 * @notice Base fork test of the request fee check against a live IPOR Fusion WithdrawManager
 *         whitelisted in prod. Skipped unless BASE_RPC_URL is set.
 */
contract GuardedExecModuleIporForkTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;

    /// @dev "Nvidia Carry Trade" vault WithdrawManager and its IPOR AccessManager
    address internal constant WITHDRAW_MANAGER = 0x7a4AaC4137d96EE075fC7862531e54a687f9A2b7;
    address internal constant ACCESS_MANAGER = 0xa70C3b442C1Eed71Cbb3b1f766A450208841Ca0C;
    /// @dev Holds ATOMIST_ROLE (100), the admin of WITHDRAW_MANAGER_REQUEST_FEE_ROLE (901)
    address internal constant ATOMIST = 0xd556a9FA4dd83aDE79B89f4A431c57169D00D4a6;
    uint64 internal constant REQUEST_FEE_ROLE = 901;
    uint256 internal constant FORK_BLOCK = 52_859_800;

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
        address[] memory targets = new address[](1);
        bytes4[] memory selectors = new bytes4[](1);
        targets[0] = WITHDRAW_MANAGER;
        selectors[0] = IWithdrawManagerAdmin.requestShares.selector;
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

        instance = makeAccountInstance("IporForkAccount");
        account = address(instance.account);
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR, module: address(guardedModule), data: ""
        });
    }

    /**
     * @notice Test: requestShares is unrestricted on the live WithdrawManager at fee 0. Once IPOR
     *         governance sets a 1% request fee, a request must fit the account's shares, one
     *         per withdraw window, and a fee above 1% is rejected.
     */
    function test_Fork_RequestSharesBoundedOnceRequestFeeIsSet() public {
        IIporWithdrawManager manager = IIporWithdrawManager(WITHDRAW_MANAGER);
        assertEq(manager.getRequestFee(), 0, "prod fee is 0");

        vm.prank(account);
        guardedModule.executeGuardedBatch(_requestShares(1e10));
        IWithdrawManagerAdmin.WithdrawRequestInfo memory pending =
            IWithdrawManagerAdmin(WITHDRAW_MANAGER).requestInfo(account);
        assertEq(pending.shares, 1e10, "request recorded");

        _setRequestFee(0.01e18);
        IERC20 vaultShares = IERC20(manager.getPlasmaVaultAddress());
        uint256 balance = 1e20;
        deal(address(vaultShares), account, balance);

        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.RequestAlreadyPending.selector,
                WITHDRAW_MANAGER,
                pending.endWithdrawWindowTimestamp
            )
        );
        guardedModule.executeGuardedBatch(_requestShares(1e10));

        vm.warp(pending.endWithdrawWindowTimestamp + 1);

        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.RequestExceedsBalance.selector,
                WITHDRAW_MANAGER,
                balance * 100,
                balance
            )
        );
        guardedModule.executeGuardedBatch(_requestShares(balance * 100));

        vm.prank(account);
        guardedModule.executeGuardedBatch(_requestShares(balance));
        assertEq(vaultShares.balanceOf(account), balance - balance / 100, "1% fee paid once");

        vm.prank(account);
        vm.expectPartialRevert(GuardedExecModuleUpgradeable.RequestAlreadyPending.selector);
        guardedModule.executeGuardedBatch(_requestShares(balance / 2));

        vm.warp(block.timestamp + 1 days + 1);
        _setRequestFee(0.02e18);
        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(
                GuardedExecModuleUpgradeable.RequestFeeTooHigh.selector, WITHDRAW_MANAGER, 0.02e18
            )
        );
        guardedModule.executeGuardedBatch(_requestShares(balance / 2));
    }

    function _setRequestFee(uint256 fee) internal {
        address feeSetter = makeAddr("feeSetter");
        vm.prank(ATOMIST);
        IIporAccessManager(ACCESS_MANAGER).grantRole(REQUEST_FEE_ROLE, feeSetter, 0);
        vm.prank(feeSetter);
        IWithdrawManagerAdmin(WITHDRAW_MANAGER).updateRequestFee(fee);
    }

    function _requestShares(uint256 shares) internal pure returns (Execution[] memory e) {
        e = new Execution[](1);
        e[0] = Execution({
            target: WITHDRAW_MANAGER,
            value: 0,
            callData: abi.encodeCall(IWithdrawManagerAdmin.requestShares, (shares))
        });
    }
}
