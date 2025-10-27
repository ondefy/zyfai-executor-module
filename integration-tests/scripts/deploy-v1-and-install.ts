import { getOwnableValidator } from '@rhinestone/module-sdk';
import { toSafeSmartAccount } from 'permissionless/accounts';
import { createSmartAccountClient } from 'permissionless';
import { erc7579Actions } from 'permissionless/actions/erc7579';
import { createPimlicoClient } from 'permissionless/clients/pimlico';
import { privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { createPublicClient, http, encodeFunctionData, fromHex, toHex } from 'viem';
import { entryPoint07Address } from 'viem/account-abstraction';
import dotenv from "dotenv";
import { join } from "path";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Deploy a new Safe account using V1 contracts (Nexus) and install GuardedExecModule
 * 
 * V1 Contracts:
 * - Safe7579 Adapter: 0x7579f2AD53b01c3D8779Fe17928e0D48885B0003
 * - Safe7579 Launchpad: 0x75798463024Bda64D83c94A64Bc7D7eaB41300eF
 * - Nexus: 0x000000000032dDC454C3BDcba80484Ad5A798705
 * - Nexus Account Factory: 0x0000000000679A258c64d2F20F310e12B64b7375
 */
async function main() {
  console.log("🚀 Starting V1 Safe deployment and module installation...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const targetRegistryAddress = process.env.TARGET_REGISTRY_ADDRESS;
  const guardedExecModuleAddress = process.env.GUARDED_EXEC_MODULE_ADDRESS;
  
  if (!privateKey || !guardedExecModuleAddress) {
    throw new Error("Missing required environment variables");
  }
  
  console.log("✅ Environment variables loaded");
  console.log("Target Registry:", targetRegistryAddress);
  console.log("Guarded Exec Module:", guardedExecModuleAddress);
  
  const eoaAccount = privateKeyToAccount(privateKey as `0x${string}`);
  const rpcUrl = process.env.BASE_RPC_URL;
  
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl),
  });
  
  // V1 Contracts (from Rhinestone docs)
  const V1_ADAPTER = '0x7579f2AD53b01c3D8779Fe17928e0D48885B0003';
  const V1_LAUNCHPAD = '0x75798463024Bda64D83c94A64Bc7D7eaB41300eF';
  
  console.log("\n🔧 Creating Safe account with V1 contracts...");
  
  // Create ownable validator
  const ownableValidator = getOwnableValidator({
    owners: [eoaAccount.address],
    threshold: 1,
  });
  
  // Create Safe account using V1 contracts
  const safeAccount = await toSafeSmartAccount({
    client: publicClient,
    owners: [eoaAccount],
    version: '1.4.1',
    entryPoint: {
      address: entryPoint07Address,
      version: '0.7',
    },
    safe4337ModuleAddress: V1_ADAPTER,
    erc7579LaunchpadAddress: V1_LAUNCHPAD,
    // NO ATTESTERS - This avoids registry hook issues
    attesters: [],
    attestersThreshold: 0,
    validators: [
      {
        address: ownableValidator.address,
        context: ownableValidator.initData,
      },
    ],
    saltNonce: fromHex(toHex(process.env.ACCOUNT_SALT || '0x1'), 'bigint'),
  });
  
  const generatedSafeAddress = await safeAccount.getAddress();
  console.log("✅ Safe account configured");
  console.log("Generated Safe address:", generatedSafeAddress);
  
  // Check if Safe account is already deployed
  const code = await publicClient.getCode({ address: generatedSafeAddress as `0x${string}` });
  const isDeployed = code && code !== '0x';
  console.log("Safe account deployed:", isDeployed ? "✅ Yes" : "❌ No - will deploy");
  
  // Create Pimlico client
  const getPimlicoUrl = (networkId: number) => {
    const apiKey = 'pim_Pj8F4e4yjMiBej7UmJjgcC';
    const baseUrl = 'https://api.pimlico.io/v2/';
    return `${baseUrl}${networkId}/rpc?apikey=${apiKey}`;
  };
  
  const pimlicoUrl = getPimlicoUrl(base.id);
  const pimlicoClient = createPimlicoClient({
    transport: http(pimlicoUrl),
    entryPoint: {
      address: entryPoint07Address,
      version: '0.7',
    },
  });
  
  const smartAccountClient = await createSmartAccountClient({
    account: safeAccount,
    chain: base,
    bundlerTransport: http(pimlicoUrl),
    paymaster: pimlicoClient,
    userOperation: {
      estimateFeesPerGas: async () => {
        return (await pimlicoClient.getUserOperationGasPrice()).fast;
      },
    },
  }).extend(erc7579Actions());
  
  // Deploy Safe account if not already deployed
  if (!isDeployed) {
    console.log("\n📦 Deploying Safe account...");
    const deploymentTx = await smartAccountClient.sendTransaction({
      to: generatedSafeAddress as `0x${string}`,
      value: 0n,
      data: '0x',
    });
    
    console.log("Deployment transaction submitted:", deploymentTx);
    
    const deploymentResult = await smartAccountClient.waitForUserOperationReceipt({
      hash: deploymentTx,
    });
    
    console.log("✅ Safe account deployed successfully!");
  } else {
    console.log("\n✅ Using existing Safe account");
  }
  
//   // Install GuardedExecModule
//   console.log("\n🔧 Installing GuardedExecModule...");
//   console.log("Module address:", guardedExecModuleAddress);
  
//   // Check if module is already installed
//   try {
//     const enabledModules = await publicClient.readContract({
//       address: generatedSafeAddress as `0x${string}`,
//       abi: [
//         {
//           inputs: [],
//           name: 'getModules',
//           outputs: [{ internalType: 'address[]', name: '', type: 'address[]' }],
//           stateMutability: 'view',
//           type: 'function',
//         },
//       ],
//       functionName: 'getModules',
//     });
    
//     console.log("Current enabled modules:", enabledModules);
    
//     if (enabledModules.includes(guardedExecModuleAddress as `0x${string}`)) {
//       console.log("✅ Module already installed - skipping");
//       return;
//     }
//   } catch (error) {
//     console.log("⚠️ Could not check existing modules, proceeding with installation...");
//   }
  
//   console.log("Installing module using ERC7579 installModule...");
  
//   // Install module using ERC7579 installModule
//   const transaction = await smartAccountClient.installModule({
//     type: 'executor',
//     address: guardedExecModuleAddress as `0x${string}`,
//     initData: '0x',
//   });
  
//   console.log("Installation transaction submitted:", transaction);
  
//   // Wait for execution
//   const result = await smartAccountClient.waitForUserOperationReceipt({
//     hash: transaction,
//   });
  
//   console.log("✅ Module installation completed!");
  
//   // Verify installation
//   try {
//     const enabledModules = await publicClient.readContract({
//       address: generatedSafeAddress as `0x${string}`,
//       abi: [
//         {
//           inputs: [],
//           name: 'getModules',
//           outputs: [{ internalType: 'address[]', name: '', type: 'address[]' }],
//           stateMutability: 'view',
//           type: 'function',
//         },
//       ],
//       functionName: 'getModules',
//     });
    
//     const isNowInstalled = enabledModules.includes(guardedExecModuleAddress as `0x${string}`);
    
//     if (isNowInstalled) {
//       console.log("✅ Module installation verified successfully");
//     } else {
//       console.log("⚠️ Module installation verification failed");
//     }
//   } catch (verifyError) {
//     console.log("⚠️ Could not verify installation:", (verifyError as Error).message);
//   }
  
//   console.log("\n🎉 V1 Safe deployment and module installation completed!");
//   console.log("Safe Address:", generatedSafeAddress);
//   console.log("\n📝 Save this address to your environment file:");
//   console.log(`SAFE_ACCOUNT_ADDRESS=${generatedSafeAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", (error as Error).message);
    process.exit(1);
  });
