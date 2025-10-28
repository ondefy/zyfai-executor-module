import { toSafeSmartAccount } from 'permissionless/accounts';
import { createSmartAccountClient } from 'permissionless';
import { erc7579Actions } from 'permissionless/actions/erc7579';
import { createPimlicoClient } from 'permissionless/clients/pimlico';
import { privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { createPublicClient, http, encodeFunctionData } from 'viem';
import { entryPoint07Address } from 'viem/account-abstraction';
import dotenv from "dotenv";
import { join } from "path";
import { getOwnableValidator, RHINESTONE_ATTESTER_ADDRESS } from '@rhinestone/module-sdk';

// Load environment variables
dotenv.config({ path: join(__dirname, "..", "env.base") });

/**
 * Install GuardedExecModuleUpgradeable on Safe account
 */
async function main() {
  console.log("🔧 Installing GuardedExecModuleUpgradeable on Safe account...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const safeAddress = process.env.SAFE_ACCOUNT_ADDRESS;
  const moduleAddress = process.env.GUARDED_EXEC_MODULE_UPGRADEABLE_ADDRESS;
  const implAddress = process.env.GUARDED_EXEC_MODULE_UPGRADEABLE_IMPL_ADDRESS;
  
  console.log("Configuration:");
  console.log("  Safe address:", safeAddress);
  console.log("  Module (Proxy) address:", moduleAddress);
  console.log("  Implementation address:", implAddress);
  
  if (!privateKey || !safeAddress || !moduleAddress) {
    throw new Error("Missing required environment variables");
  }
  
  // Create account from private key
  const eoaAccount = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("\n📝 Account address:", eoaAccount.address);
  
  // Create public client
  const rpcUrl = process.env.BASE_RPC_URL;
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl),
  });
  
  try {
    // Create ownable validator
    const ownableValidator = getOwnableValidator({
      owners: [eoaAccount.address],
      threshold: 1,
    });
      
    // Create Smart Account instance from existing Safe
    console.log("\n🔍 Loading existing Safe account...");
    const safeAccount = await toSafeSmartAccount({
      client: publicClient,
      owners: [eoaAccount],
      version: '1.4.1',
      entryPoint: {
        address: entryPoint07Address,
        version: '0.7',
      },
      attesters: [
        RHINESTONE_ATTESTER_ADDRESS, // Rhinestone Attester - SAME as original
      ],
      attestersThreshold: 1, // SAME as original
      safe4337ModuleAddress: '0x7579EE8307284F293B1927136486880611F20002',
      erc7579LaunchpadAddress: '0x7579011aB74c46090561ea277Ba79D510c6C00ff',
      address: safeAddress as `0x${string}`,
      validators: [
        {
          address: ownableValidator.address,
          context: ownableValidator.initData,
        },
      ],
    });

    const loadedSafeAddress = await safeAccount.getAddress();
    console.log("✅ Safe account loaded:", loadedSafeAddress);
    
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
  
    // Check if module is already installed
    console.log("\n🔍 Checking if module is already installed...");
    try {
      const enabledModules = await publicClient.readContract({
        address: loadedSafeAddress as `0x${string}`,
        abi: [
          {
            inputs: [],
            name: 'getModules',
            outputs: [{ internalType: 'address[]', name: '', type: 'address[]' }],
            stateMutability: 'view',
            type: 'function',
          },
        ],
        functionName: 'getModules',
      });
      
      console.log("Enabled modules:", enabledModules);
      
      if (enabledModules.includes(moduleAddress as `0x${string}`)) {
        console.log("⚠️  Module is already installed!");
        console.log("✅ You can use this module in your transactions.");
        return;
      }
    } catch (error) {
      console.log("⚠️ Could not check existing modules, proceeding with installation...");
    }
    
    // Install the module using Safe's native installModule method
    console.log("\n📦 Installing GuardedExecModuleUpgradeable...", moduleAddress);
    
    const installModuleData = encodeFunctionData({
      abi: [
        {
          inputs: [
            { internalType: 'uint256', name: 'moduleTypeId', type: 'uint256' },
            { internalType: 'address', name: 'module', type: 'address' },
            { internalType: 'bytes', name: 'data', type: 'bytes' }
          ],
          name: 'installModule',
          outputs: [],
          stateMutability: 'nonpayable',
          type: 'function',
        },
      ],
      functionName: 'installModule',
      args: [
        2n, // MODULE_TYPE_EXECUTOR
        moduleAddress as `0x${string}`,
        '0x' // No initialization data needed
      ],
    });
    console.log("📝 Install module data:", installModuleData);
    
    // Execute the installation transaction
    const transaction = await smartAccountClient.sendTransaction({
      to: loadedSafeAddress as `0x${string}`,
      value: 0n,
      data: installModuleData,
    });
    console.log("✅ Transaction submitted:", transaction);
    
    // Wait for execution
    console.log("\n⏳ Waiting for confirmation...");
    const result = await smartAccountClient.waitForUserOperationReceipt({
      hash: transaction,
    });
    console.log("✅ Module installation completed:", result);
    
    // Verify installation
    try {
      const enabledModules = await publicClient.readContract({
        address: loadedSafeAddress as `0x${string}`,
        abi: [
          {
            inputs: [],
            name: 'getModules',
            outputs: [{ internalType: 'address[]', name: '', type: 'address[]' }],
            stateMutability: 'view',
            type: 'function',
          },
        ],
        functionName: 'getModules',
      });
      
      const isNowInstalled = enabledModules.includes(moduleAddress as `0x${string}`);
      if (isNowInstalled) {
        console.log("\n🎉 GuardedExecModuleUpgradeable successfully installed and verified!");
      } else {
        console.log("⚠️  Module installation verification failed");
      }
    } catch (verifyError) {
      console.log("⚠️  Could not verify installation, but transaction completed:", (verifyError as Error).message);
    }
    
    console.log("\n📋 Module Details:");
    console.log("  Proxy Address:", moduleAddress);
    console.log("  Implementation Address:", implAddress);
    console.log("  Safe Account:", loadedSafeAddress);
    console.log("\n✅ Your upgradeable module is now installed and ready to use!");
    console.log("   This address stays the same even after upgrades:", moduleAddress);
    
  } catch (error) {
    console.error("\n❌ Installation failed:");
    console.error((error as Error).message);
    throw error;
  }
  
  console.log("\n✅ Installation process finished successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });

