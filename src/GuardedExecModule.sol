// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// 🔁 use the paths that match your ModuleKit version"modulekit/Modules.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
// If you have a constant for the type, import it; otherwise hardcode 2 (Executor)
import { ITargetRegistry } from "./TargetRegistry.sol";
import "forge-std/console.sol";

/**
 * Public surface you call from the SDK.
 * Inside, we delegatecall the stateless GuardedRouter in the account context.
 */
contract GuardedExecModule is ERC7579ExecutorBase {
    // Per-account storage
    mapping(address => ITargetRegistry) public registry;   // per-account setting (set on install)
    mapping(address => address) public router;             // stateless GuardedRouter per account

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
        // Module is considered initialized if it has a registry set for this account
        return address(registry[smartAccount]) != address(0);
    }

    // ---------- Install / Uninstall ----------
    // data = abi.encode(address registry_, address router_)
    function onInstall(bytes calldata data) external override {
        (address reg, address rtr) = abi.decode(data, (address, address));
        registry[msg.sender] = ITargetRegistry(reg);
        router[msg.sender]   = rtr;
    }

    function onUninstall(bytes calldata) external override {
        // Clean up storage for this account
        delete registry[msg.sender];
        delete router[msg.sender];
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
        
        // Get the registry and router for the calling account
        ITargetRegistry accountRegistry = registry[msg.sender];
        address accountRouter = router[msg.sender];
        
        console.log("Smart Account:", msg.sender);
        console.log("Registry:", address(accountRegistry));
        console.log("Router:", accountRouter);
        
        require(address(accountRegistry) != address(0), "not-initialized");
        
        // Optional pre-check (router also checks):
        console.log("\nPre-check: Verifying all targets are whitelisted...");
        for (uint256 i = 0; i < targets.length; i++) {
            bool whitelisted = accountRegistry.isWhitelisted(targets[i]);
            console.log("Target #%d:", i);
            console.log("  Address:", targets[i]);
            console.log("  Whitelisted:", whitelisted);
            require(whitelisted, "not-whitelisted");
        }
        console.log("Pre-check passed!\n");

        // Build router calldata
        bytes memory routerData = abi.encodeWithSignature(
            "guardedBatch(address,address[],bytes[],bool)",
            address(accountRegistry),
            targets,
            calldatas,
            revertAll
        );

        console.log("Calling _executeDelegateCall to router...");
        console.log("This will ask the smart account to delegatecall the router");
        
        // This uses msg.sender (the ACCOUNT) under the hood and performs a DELEGATECALL to `router`
        _executeDelegateCall(accountRouter, routerData);
        
        console.log("\nGuarded batch execution completed!");
        console.log("========================================\n");
    }
}