// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Create3Factory} from "../src/utils/Create3Factory.sol";
import {GuardedExecModuleUpgradeable} from "../src/module/GuardedExecModuleUpgradeable.sol";

// Nick's deterministic deployer on most EVM chains
address constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

contract DeployWithCREATE3 is Script {
    // Use fixed salts to keep addresses identical across chains
    bytes32 constant FACTORY_SALT = keccak256("zyfai-create3-factory-v1");
    bytes32 constant IMPL_SALT    = keccak256("GuardedExecModuleUpgradeable-impl-v1");
    bytes32 constant PROXY_SALT   = keccak256("GuardedExecModuleUpgradeable-proxy-v1");

    function run() external {
        uint256 pk       = vm.envUint("PRIVATE_KEY");   // signer
        address guardian = vm.addr(pk);                 // use as init guardian or owner as you wish
        address owner    = guardian;
        address registry = vm.envAddress("TARGET_REGISTRY_ADDRESS"); // may differ per chain

        vm.startBroadcast(pk);

        // === 0) Deploy the CREATE3 factory itself deterministically via 0x4e59 ===
        bytes memory factoryCode = type(Create3Factory).creationCode;
        address predictedFactory = Create2.computeAddress(
            FACTORY_SALT, keccak256(factoryCode), CREATE2_FACTORY
        );
        if (_codeSize(predictedFactory) == 0) {
            (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(FACTORY_SALT, factoryCode));
            require(ok, "deploy factory via 0x4e59 failed");
            require(_codeSize(predictedFactory) > 0, "factory not deployed");
        }
        Create3Factory factory = Create3Factory(predictedFactory);

        // === 1) Deploy IMPLEMENTATION via CREATE3 (address depends only on salt) ===
        // Implementation constructor takes no args (it's upgradeable)
        bytes memory implCode = type(GuardedExecModuleUpgradeable).creationCode;
        address implPred = factory.compute(IMPL_SALT);
        if (_codeSize(implPred) == 0) {
            implPred = factory.deploy(IMPL_SALT, implCode);
        }
        address impl = implPred;

        // === 2) Deploy PROXY via CREATE3 with initializer in constructor (OK!) ===
        // With CREATE3, init data can vary per chain without changing the address.
        bytes memory initData = abi.encodeCall(
            GuardedExecModuleUpgradeable.initialize, (registry, owner)
        );
        bytes memory proxyCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(impl, initData)
        );
        address proxyPred = factory.compute(PROXY_SALT);
        if (_codeSize(proxyPred) == 0) {
            proxyPred = factory.deploy(PROXY_SALT, proxyCode);
        }
        address proxy = proxyPred;

        vm.stopBroadcast();

        console.log("CREATE3 factory :", address(factory));
        console.log("Implementation  :", impl);
        console.log("Proxy           :", proxy);
    }

    function _codeSize(address a) internal view returns (uint256 s) {
        assembly { s := extcodesize(a) }
    }
}

