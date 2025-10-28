import { getOwnableValidator, getAccount, RHINESTONE_ATTESTER_ADDRESS } from '@rhinestone/module-sdk';
import { toSafeSmartAccount } from 'permissionless/accounts';
import { createSmartAccountClient } from 'permissionless';
import { erc7579Actions } from 'permissionless/actions/erc7579';
import { createPimlicoClient } from 'permissionless/clients/pimlico';
import { privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { createPublicClient, createWalletClient, http, encodeFunctionData, fromHex, toHex } from 'viem';
import { entryPoint07Address } from 'viem/account-abstraction';
import dotenv from "dotenv";
import { join } from "path";
import { readFileSync } from "fs";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Install GuardedExecModule on Safe account using Rhinestone SDK
 */
async function main() {
  console.log("🔧 Installing GuardedExecModule on Safe account...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const safeAddress = process.env.SAFE_ACCOUNT_ADDRESS;
  const moduleAddress = process.env.GUARDED_EXEC_MODULE_ADDRESS;
  console.log("Private key:", privateKey);
  console.log("Safe address:", safeAddress);
  console.log("Module address:", moduleAddress);
  
  if (!privateKey || !safeAddress || !moduleAddress) {
    throw new Error("Missing required environment variables. Please run create-safe-account.ts first");
  }
  
  console.log("Safe address:", safeAddress);
  console.log("Module address:", moduleAddress);
  
  // Create account from private key
  const account = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("Account address:", account.address);
  
  // Create public client with proper RPC URL
  const rpcUrl = process.env.BASE_RPC_URL;
  console.log("Using RPC URL:", rpcUrl);
  
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl),
  });
  
  // Create ownable validator
  const ownableValidator = getOwnableValidator({
    owners: [account.address],
    threshold: 1,
  });
  
  // Create Safe account using toSafeSmartAccount
  const safeAccount = await toSafeSmartAccount({
    client: publicClient,
    owners: [account],
    version: '1.4.1',
    entryPoint: {
      address: entryPoint07Address,
      version: '0.7',
    },
    safe4337ModuleAddress: '0x7579EE8307284F293B1927136486880611F20002',
    erc7579LaunchpadAddress: '0x7579011aB74c46090561ea277Ba79D510c6C00ff',
    attesters: [
      RHINESTONE_ATTESTER_ADDRESS, // Rhinestone Attester
    ],
    attestersThreshold: 1,
    validators: [
      {
        address: ownableValidator.address,
        context: ownableValidator.initData,
      },
    ],
    saltNonce: fromHex(toHex(process.env.ACCOUNT_SALT || '0x1'), 'bigint'),
  });
  
  // Create Pimlico client with proper URL
  const getPimlicoUrl = (networkId: number) => {
    const apiKey = 'pim_Pj8F4e4yjMiBej7UmJjgcC';
    const baseUrl = 'https://api.pimlico.io/v2/';
    return `${baseUrl}${networkId}/rpc?apikey=${apiKey}`;
  };
  
  const pimlicoUrl = getPimlicoUrl(base.id);
  console.log("Pimlico URL:", pimlicoUrl);
  
  const pimlicoClient = createPimlicoClient({
    transport: http(pimlicoUrl),
    entryPoint: {
      address: entryPoint07Address,
      version: '0.7',
    },
  });
  
  const smartAccountClient = createSmartAccountClient({
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
  
  console.log("\n🔍 Checking if Safe account is deployed...");
  
  // First check if the Safe account is deployed
  const code = await publicClient.getCode({ address: safeAddress as `0x${string}` });
  console.log("Safe account code length:", code?.length || 0);
  
  if (!code || code === '0x') {
    console.log("❌ Safe account is not deployed yet. Please run create-safe-account.ts first");
    return;
  }
  
  console.log("✅ Safe account is deployed");
  
  console.log("\n🔍 Checking if this is a Safe account...");
  
  // Check if this is actually a Safe account by reading its threshold
  try {
    const threshold = await publicClient.readContract({
      address: safeAddress as `0x${string}`,
      abi: [
        {
          inputs: [],
          name: 'getThreshold',
          outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
          stateMutability: 'view',
          type: 'function',
        },
      ],
      functionName: 'getThreshold',
    });
    console.log("Safe threshold:", threshold.toString());
  } catch (error) {
    console.log("❌ This is not a Safe account:", (error as Error).message);
    return;
  }
  
  console.log("\n🔍 Checking module installation status...");
  console.log("moduleAddress: ", moduleAddress);

  // Check if module is already installed using ERC7579 methods
  let isInstalled = false;
  try {
    isInstalled = await smartAccountClient.isModuleInstalled({
      address: moduleAddress as `0x${string}`,
      type: 'executor',
      context: '0x',
    });
    console.log("Is installed:", isInstalled);
  } catch (error) {
    console.log("⚠️ Could not check module installation status:", (error as Error).message);
    console.log("Proceeding with installation...");
  }
  
  if (isInstalled) {
    console.log("✅ GuardedExecModule is already installed");
    return;
  }
  
  console.log("📦 Installing GuardedExecModule using ERC7579 installModule...");
  
  try {
    // Use ERC7579 installModule method
    const transaction = await smartAccountClient.installModule({
      address: moduleAddress as `0x${string}`,
      type: 'executor',
      context: '0x', // No initialization data needed
    });
    
    console.log("Transaction submitted:", transaction);
    
    // Wait for execution
    const result = await smartAccountClient.waitForUserOperationReceipt({
      hash: transaction,
    });
    console.log("✅ Module installation completed:", result);
    
    // Verify installation
    try {
      const isNowInstalled = await smartAccountClient.isModuleInstalled({
        address: moduleAddress as `0x${string}`,
        type: 'executor',
        context: '0x',
      });
      console.log("Is now installed:", isNowInstalled);
      
      if (isNowInstalled) {
        console.log("✅ GuardedExecModule successfully installed and verified");
      } else {
        console.log("❌ Module installation verification failed");
      }
    } catch (verifyError) {
      console.log("⚠️ Could not verify installation, but transaction completed:", (verifyError as Error).message);
    }
    
    console.log("\n📝 Next steps:");
    console.log("1. Run: pnpm run create-session-key");
    console.log("2. Run: pnpm run test-integration");
  } catch (error) {
    console.error("❌ Error installing module:", (error as Error).message);
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error installing module:", error);
    process.exit(1);
  });