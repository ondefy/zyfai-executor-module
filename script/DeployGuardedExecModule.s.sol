// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.23;

// import "forge-std/Script.sol";
// import { RegistryDeployer } from "modulekit/deployment/RegistryDeployer.sol";
// import { GuardedExecModule } from "../src/GuardedExecModule.sol";
// import { TargetRegistry } from "../src/TargetRegistry.sol";

// /// @title DeployGuardedExecModuleScript
// /// @notice Deploys GuardedExecModule using RegistryDeployer and links it with TargetRegistry
// contract DeployGuardedExecModuleScript is Script, RegistryDeployer {
//     function run() public {
//         // Get private key for deployment
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         address deployerAddress = vm.addr(deployerPrivateKey);
        
//         console.log("Deployer address:", deployerAddress);
        
//         vm.startBroadcast(deployerPrivateKey);
        
//         // First, deploy the TargetRegistry
//         console.log("Deploying TargetRegistry...");
//         TargetRegistry targetRegistry = new TargetRegistry(deployerAddress);
//         console.log("TargetRegistry deployed at:", address(targetRegistry));
        
//         // Deploy GuardedExecModule with TargetRegistry address
//         console.log("Deploying GuardedExecModule...");
//         GuardedExecModule guardedExecModule = new GuardedExecModule(address(targetRegistry), deployerAddress);
//         console.log("GuardedExecModule deployed at:", address(guardedExecModule));
        
//         vm.stopBroadcast();
        
//         // Save addresses to deployments.txt
//         string memory deploymentData = string(abi.encodePacked(
//             "TARGET_REGISTRY=", vm.toString(address(targetRegistry)), "\n",
//             "GUARDED_EXEC_MODULE=", vm.toString(address(guardedExecModule)), "\n",
//             "DEPLOYER=", vm.toString(deployerAddress), "\n"
//         ));
        
//         vm.writeFile("deployments.txt", deploymentData);
        
//         console.log("\n✅ Deployment completed successfully!");
//         console.log("TargetRegistry:", address(targetRegistry));
//         console.log("GuardedExecModule:", address(guardedExecModule));
//         console.log("Addresses saved to deployments.txt");
//     }
// }
