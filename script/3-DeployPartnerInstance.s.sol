// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { GuardedExecModuleUpgradeable } from "../src/module/GuardedExecModuleUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TargetRegistry } from "../src/registry/TargetRegistry.sol";

/**
 * @title Deploy Partner Instance
 * @notice Deploys a dedicated TargetRegistry + GuardedExecModuleUpgradeable (impl + proxy) pair
 *         for a partner, owned by the DEPLOYER so the whitelist can be configured before
 *         ownership is handed over.
 * @dev The module implementation pins the partner Adapter (the only allowed grantee), so the
 *      partner Adapter must be deployed first. Run with:
 *      PARTNER_ADAPTER=0x... \
 *      forge script script/3-DeployPartnerInstance.s.sol --rpc-url $RPC_URL \
 *        --private-key $PRIVATE_KEY --broadcast --verify -vvvv
 *
 * WORKFLOW (partner hand-over):
 *   1. Deploy the partner Adapter (defi-adapter), then run this script — registry + module are
 *      deployed with the deployer as owner.
 *   2. Whitelist the partner venues on the new registry (e.g. script/5-WhitelistPartnerNvda.s.sol).
 *   3. Transfer ownership of all four contracts to the partner:
 *        script/4-TransferPartnerOwnership.s.sol
 */
contract DeployPartnerInstance is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address adapter = vm.envAddress("PARTNER_ADAPTER");
        require(adapter.code.length > 0, "PARTNER_ADAPTER has no code");

        console.log("=== Deploying Partner Instance (registry + module) ===");
        console.log("Deployer (temporary owner):", deployer);
        console.log("Partner adapter:", adapter);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Dedicated TargetRegistry, owned by the deployer for whitelist setup.
        console.log("\n--- Step 1: Deploy TargetRegistry ---");
        TargetRegistry registry = new TargetRegistry(deployer);
        console.log("TargetRegistry deployed to:", address(registry));

        // Step 2: Module implementation.
        console.log("\n--- Step 2: Deploy GuardedExecModuleUpgradeable implementation ---");
        GuardedExecModuleUpgradeable implementation = new GuardedExecModuleUpgradeable(adapter);
        console.log("Implementation deployed to:", address(implementation));

        // Step 3: ERC1967 proxy wired to the partner registry, owned by the deployer.
        console.log("\n--- Step 3: Deploy proxy ---");
        bytes memory initData = abi.encodeWithSelector(
            GuardedExecModuleUpgradeable.initialize.selector, address(registry), deployer
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed to:", address(proxy));

        vm.stopBroadcast();

        // Verification
        GuardedExecModuleUpgradeable module = GuardedExecModuleUpgradeable(address(proxy));
        assert(registry.owner() == deployer);
        assert(module.owner() == deployer);
        assert(address(module.registry()) == address(registry));
        assert(module.ADAPTER() == adapter);

        console.log("\n=== Deployment Success ===");
        console.log("TargetRegistry:", address(registry));
        console.log("Module implementation:", address(implementation));
        console.log("Module proxy:", address(proxy));
        console.log("Owner (both):", deployer);

        console.log("\n=== Next Steps ===");
        console.log("1. Verify the three contracts on the block explorer");
        console.log("2. Whitelist the partner venues (script/5-WhitelistPartnerNvda.s.sol)");
        console.log("3. Run script/4-TransferPartnerOwnership.s.sol to hand over ownership");
    }
}
