// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// 🔁 use the paths that match your ModuleKit version"modulekit/Modules.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
// If you have a constant for the type, import it; otherwise hardcode 2 (Executor)
import { ITargetRegistry } from "./TargetRegistry.sol";
import "forge-std/console.sol";

/**
 * @title GuardedExecModule
 * @notice Secure executor module with immutable registry/router configuration
 * @dev Registry and router are set at deployment time and cannot be changed
 *      to prevent malicious overwrites via onInstall()
 */
contract GuardedExecModule is ERC7579ExecutorBase {
    // SECURITY: Immutable registry and router set at deployment
    ITargetRegistry public immutable registry;
    address public immutable router;

    // ---------- Module metadata ----------
    function name() external pure returns (string memory) { return "GuardedExecModule"; }
    function version() external pure returns (string memory) { return "0.1.0"; }

    // ERC-7579: declare this as an EXECUTOR module (use your framework's constant if available)
    function isModuleType(uint256 typeId) external pure override returns (bool) {
        // MODULE_TYPE_EXECUTOR == 2 in reference implementations
        return typeId == 2;
    }

    // Check if module is initialized for a specific smart account
    function isInitialized(address smartAccount) external view override returns (bool) {
        // Module is always "initialized" since registry/router are immutable
        return true;
    }

    // ---------- Constructor (SECURITY: Set registry/router at deployment) ----------
    constructor(address _registry, address _router) {
        require(_registry != address(0), "invalid-registry");
        require(_router != address(0), "invalid-router");
        registry = ITargetRegistry(_registry);
        router = _router;
    }

    // ---------- Install / Uninstall ----------
    function onInstall(bytes calldata) external override {
        // No-op: Registry and router are immutable
    }

    function onUninstall(bytes calldata) external override {
        // No-op: Nothing to clean up
    }

    // ---------- Public entrypoint you call from the SDK ----------
    function executeGuardedBatch(
        address[] calldata targets,
        bytes[]  calldata calldatas,
        bool revertAll
    ) external {
        console.log("\n========================================");
        console.log("GuardedExecModule.executeGuardedBatch()");
        console.log("========================================");
        console.log("Called by (session key/EOA):", msg.sender);
        console.log("Module address (this):", address(this));
        
        console.log("Smart Account:", msg.sender);
        console.log("Registry:", address(registry));
        console.log("Router:", router);
        
        require(targets.length == calldatas.length, "length-mismatch");
        require(targets.length > 0, "empty-batch");
        
        // Pre-check (router also checks):
        console.log("\nPre-check: Verifying all targets are whitelisted...");
        for (uint256 i = 0; i < targets.length; i++) {
            bool whitelisted = registry.isWhitelisted(targets[i]);
            console.log("Target #%d:", i);
            console.log("  Address:", targets[i]);
            console.log("  Whitelisted:", whitelisted);
            require(whitelisted, "not-whitelisted");
        }
        console.log("Pre-check passed!\n");

        // Build router calldata
        bytes memory routerData = abi.encodeWithSignature(
            "guardedBatch(address,address[],bytes[],bool)",
            address(registry),
            targets,
            calldatas,
            revertAll
        );

        console.log("Calling _executeDelegateCall to router...");
        console.log("This will ask the smart account to delegatecall the router");
        
        // This uses msg.sender (the ACCOUNT) under the hood and performs a DELEGATECALL to `router`
        _executeDelegateCall(router, routerData);
        
        console.log("\nGuarded batch execution completed!");
        console.log("========================================\n");
    }
}