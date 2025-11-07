// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { GuardedExecModuleUpgradeable } from "../src/module/GuardedExecModuleUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployUpgradeableSimple is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address registryAddress = 0xA0BeE327A95F786F5097028EE250C4834DFEB629;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying GuardedExecModuleUpgradeable...");
        console.log("Deployer:", deployer);
        console.log("Registry:", registryAddress);

        // Deploy implementation
        GuardedExecModuleUpgradeable implementation = new GuardedExecModuleUpgradeable();
        console.log("Implementation:", address(implementation));

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            GuardedExecModuleUpgradeable.initialize.selector, registryAddress, deployer
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
