// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { GuardedExecModuleUpgradeable } from "../src/module/GuardedExecModuleUpgradeable.sol";
import { TargetRegistry } from "../src/registry/TargetRegistry.sol";

/**
 * @title Transfer Partner Ownership
 * @notice Initiates the two-step ownership transfer of a partner TargetRegistry and
 *         GuardedExecModule proxy to the partner's wallet. Run AFTER the whitelist has been
 *         cloned (addToWhitelist is onlyOwner, so configuration must happen before hand-over).
 * @dev Both contracts are Ownable2Step: this script only calls transferOwnership; the partner
 *      MUST call acceptOwnership() on both contracts from PARTNER_OWNER to complete the
 *      transfer. Until then the deployer remains the owner.
 *
 *      Run with:
 *      PARTNER_OWNER=0x... \
 *      PARTNER_TARGET_REGISTRY=0x... \
 *      PARTNER_GUARDED_EXEC_MODULE=0x... \
 *      forge script script/4-TransferPartnerOwnership.s.sol --rpc-url $RPC_URL \
 *        --private-key $PRIVATE_KEY --broadcast -vvvv
 *
 *      SECURITY: the partner owner should be a multisig. The module owner holds UUPS upgrade
 *      rights, which is de-facto custody over every wallet that installs the module.
 */
contract TransferPartnerOwnership is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address partnerOwner = vm.envAddress("PARTNER_OWNER");
        address registryAddress = vm.envAddress("PARTNER_TARGET_REGISTRY");
        address moduleAddress = vm.envAddress("PARTNER_GUARDED_EXEC_MODULE");

        require(partnerOwner != address(0), "PARTNER_OWNER is zero");

        TargetRegistry registry = TargetRegistry(registryAddress);
        GuardedExecModuleUpgradeable module = GuardedExecModuleUpgradeable(moduleAddress);

        console.log("=== Transferring Partner Ownership (two-step) ===");
        console.log("Deployer (current owner):", deployer);
        console.log("Partner owner:", partnerOwner);
        console.log("TargetRegistry:", registryAddress);
        console.log("Module proxy:", moduleAddress);

        // Sanity: we own both, and the module is wired to THIS registry.
        require(registry.owner() == deployer, "Deployer does not own the registry");
        require(module.owner() == deployer, "Deployer does not own the module");
        require(
            address(module.registry()) == registryAddress,
            "Module is not wired to PARTNER_TARGET_REGISTRY"
        );

        vm.startBroadcast(deployerPrivateKey);

        registry.transferOwnership(partnerOwner);
        console.log("Registry ownership transfer initiated");

        module.transferOwnership(partnerOwner);
        console.log("Module ownership transfer initiated");

        vm.stopBroadcast();

        // Verification: pending owner set, current owner unchanged until acceptance.
        assert(registry.pendingOwner() == partnerOwner);
        assert(module.pendingOwner() == partnerOwner);

        console.log("\n=== Transfer Initiated ===");
        console.log("Pending owner (both contracts):", partnerOwner);
        console.log("\n=== Next Steps (PARTNER) ===");
        console.log("The partner must call acceptOwnership() FROM", partnerOwner);
        console.log("  1. On TargetRegistry:", registryAddress);
        console.log("  2. On module proxy:", moduleAddress);
        console.log("Until both calls land, the deployer remains the owner.");
    }
}
