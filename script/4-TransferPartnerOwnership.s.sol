// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { GuardedExecModuleUpgradeable } from "../src/module/GuardedExecModuleUpgradeable.sol";
import { TargetRegistry } from "../src/registry/TargetRegistry.sol";

/// Minimal surface of the partner Adapter proxy (Ownable2StepUpgradeable, lives in defi-adapter).
interface IOwnable2Step {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

/// Minimal surface of the Adapter's UpgradeableBeacon (plain Ownable — ONE-step transfer).
interface IOwnableBeacon {
    function owner() external view returns (address);
    function implementation() external view returns (address);
    function transferOwnership(address newOwner) external;
}

/**
 * @title Transfer Partner Ownership
 * @notice Initiates the ownership transfer of ALL FOUR partner contracts to the partner's
 *         wallet: TargetRegistry, GuardedExecModule proxy, Adapter proxy, and the Adapter's
 *         UpgradeableBeacon. Run AFTER the whitelist has been cloned (addToWhitelist is
 *         onlyOwner, so configuration must happen before hand-over).
 * @dev Registry, module and adapter are Ownable2Step: this script only calls
 *      transferOwnership; the partner MUST call acceptOwnership() on all three from
 *      PARTNER_OWNER to complete the transfer. Until then the deployer remains the owner.
 *
 *      The BEACON IS DIFFERENT: it is a plain Ownable, so its transfer completes
 *      IMMEDIATELY in this script — triple-check PARTNER_OWNER before broadcasting.
 *      The beacon owner controls the Adapter's implementation (de-facto custody over
 *      every approval granted to the adapter), so it must move with the other three.
 *
 *      Run with:
 *      PARTNER_OWNER=0x... \
 *      PARTNER_TARGET_REGISTRY=0x... \
 *      PARTNER_GUARDED_EXEC_MODULE=0x... \
 *      PARTNER_ADAPTER=0x... \
 *      PARTNER_ADAPTER_BEACON=0x... \
 *      forge script script/4-TransferPartnerOwnership.s.sol --rpc-url $RPC_URL \
 *        --private-key $PRIVATE_KEY --broadcast -vvvv
 *
 *      SECURITY: the partner owner should be a multisig. The module owner holds UUPS upgrade
 *      rights and the beacon owner holds adapter upgrade rights — both are de-facto custody
 *      over every wallet that installs the module / approves the adapter.
 */
contract TransferPartnerOwnership is Script {
    /// EIP-1967 beacon slot: bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
    bytes32 internal constant BEACON_SLOT =
        0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address partnerOwner = vm.envAddress("PARTNER_OWNER");
        address registryAddress = vm.envAddress("PARTNER_TARGET_REGISTRY");
        address moduleAddress = vm.envAddress("PARTNER_GUARDED_EXEC_MODULE");
        address adapterAddress = vm.envAddress("PARTNER_ADAPTER");
        address beaconAddress = vm.envAddress("PARTNER_ADAPTER_BEACON");

        require(partnerOwner != address(0), "PARTNER_OWNER is zero");

        TargetRegistry registry = TargetRegistry(registryAddress);
        GuardedExecModuleUpgradeable module = GuardedExecModuleUpgradeable(moduleAddress);
        IOwnable2Step adapter = IOwnable2Step(adapterAddress);
        IOwnableBeacon beacon = IOwnableBeacon(beaconAddress);

        console.log("=== Transferring Partner Ownership (all four contracts) ===");
        console.log("Deployer (current owner):", deployer);
        console.log("Partner owner:", partnerOwner);
        console.log("TargetRegistry:", registryAddress);
        console.log("Module proxy:", moduleAddress);
        console.log("Adapter proxy:", adapterAddress);
        console.log("Adapter beacon:", beaconAddress);

        // Sanity: we own all four, the module is wired to THIS registry, and the beacon is
        // really the one behind the adapter proxy (EIP-1967 beacon slot).
        require(registry.owner() == deployer, "Deployer does not own the registry");
        require(module.owner() == deployer, "Deployer does not own the module");
        require(adapter.owner() == deployer, "Deployer does not own the adapter");
        require(beacon.owner() == deployer, "Deployer does not own the beacon");
        require(
            address(module.registry()) == registryAddress,
            "Module is not wired to PARTNER_TARGET_REGISTRY"
        );
        require(
            address(uint160(uint256(vm.load(adapterAddress, BEACON_SLOT)))) == beaconAddress,
            "PARTNER_ADAPTER_BEACON is not the adapter's beacon"
        );

        console.log("Adapter implementation (via beacon):", beacon.implementation());

        vm.startBroadcast(deployerPrivateKey);

        registry.transferOwnership(partnerOwner);
        console.log("Registry ownership transfer initiated (2-step)");

        module.transferOwnership(partnerOwner);
        console.log("Module ownership transfer initiated (2-step)");

        adapter.transferOwnership(partnerOwner);
        console.log("Adapter ownership transfer initiated (2-step)");

        // ONE-STEP: effective immediately.
        beacon.transferOwnership(partnerOwner);
        console.log("Beacon ownership TRANSFERRED (one-step, effective now)");

        vm.stopBroadcast();

        // Verification: pending owner set on the three 2-step contracts, beacon already moved.
        assert(registry.pendingOwner() == partnerOwner);
        assert(module.pendingOwner() == partnerOwner);
        assert(adapter.pendingOwner() == partnerOwner);
        assert(beacon.owner() == partnerOwner);

        console.log("\n=== Transfer State ===");
        console.log("Pending owner (registry, module, adapter):", partnerOwner);
        console.log("Beacon owner (already effective):", partnerOwner);
        console.log("\n=== Next Steps (PARTNER) ===");
        console.log("The partner must call acceptOwnership() FROM", partnerOwner);
        console.log("  1. On TargetRegistry:", registryAddress);
        console.log("  2. On module proxy:", moduleAddress);
        console.log("  3. On adapter proxy:", adapterAddress);
        console.log("Until those calls land, the deployer remains the owner of the three");
        console.log("2-step contracts. The beacon is already owned by the partner.");
        console.log("\nOn-chain verification for the partner:");
        console.log("  owner() + pendingOwner() on registry/module/adapter, owner() on beacon.");
    }
}
