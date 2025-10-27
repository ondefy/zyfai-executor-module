import { getOwnableValidator, getAccount, RHINESTONE_ATTESTER_ADDRESS } from '@rhinestone/module-sdk';
import { toSafeSmartAccount } from 'permissionless/accounts';
import { createSmartAccountClient } from 'permissionless';
import { erc7579Actions } from 'permissionless/actions/erc7579';
import { createPimlicoClient } from 'permissionless/clients/pimlico';
import { privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { createPublicClient, createWalletClient, http, fromHex, toHex } from 'viem';
import { entryPoint07Address } from 'viem/account-abstraction';
import dotenv from "dotenv";
import { join } from "path";
import { readFileSync } from "fs";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Remove registry hook from existing Safe account to allow custom module installation
 */
async function main() {
  console.log("🔧 Removing registry hook from Safe account...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const safeAddress = process.env.SAFE_ACCOUNT_ADDRESS;
  console.log("Private key:", privateKey);
  console.log("Safe address:", safeAddress);
  
  if (!privateKey || !safeAddress) {
    throw new Error("Missing required environment variables. Please run create-safe-account.ts first");
  }
  
  // Create account from private key
  const account = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("Account address:", account.address);
  
  // Create public client with proper RPC URL
  const rpcUrl = process.env.BASE_RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/5Uo86gAvWS1DPR3voM9Q2o0JFuJU30Uc';
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
  
  console.log("\n🔍 Checking installed modules...");
  
  try {
    // Get all installed modules using ERC7579 methods
    const modules = await smartAccountClient.getModulesByType({
      type: 'hook', // Registry hook is a hook module
    });
    
    console.log("Installed hook modules:", modules);
    
    // Look for registry hook modules
    const registryHookModules = modules.filter((module: string) => 
      module.toLowerCase().includes('registry') || 
      module.toLowerCase().includes('hook')
    );
    
    if (registryHookModules.length === 0) {
      console.log("✅ No registry hook modules found. Safe account is ready for custom modules.");
      return;
    }
    
    console.log("Found registry hook modules:", registryHookModules);
    
    // Remove each registry hook module
    for (const moduleAddress of registryHookModules) {
      console.log(`🗑️ Removing registry hook module: ${moduleAddress}`);
      
      try {
        const transaction = await smartAccountClient.uninstallModule({
          address: moduleAddress as `0x${string}`,
          type: 'hook',
          context: '0x',
        });
        
        console.log("Transaction submitted:", transaction);
        
        // Wait for execution
        const result = await smartAccountClient.waitForUserOperationReceipt({
          hash: transaction,
        });
        
        console.log("✅ Registry hook module removed:", result);
        
      } catch (error) {
        console.error(`❌ Error removing module ${moduleAddress}:`, (error as Error).message);
      }
    }
    
    console.log("\n✅ Registry hook removal completed");
    console.log("\n📝 Next steps:");
    console.log("1. Run: pnpm run install-module");
    console.log("2. Run: pnpm run setup-whitelist");
    console.log("3. Run: pnpm run create-session-key");
    console.log("4. Run: pnpm run test-integration");
    
  } catch (error) {
    console.error("❌ Error checking modules:", (error as Error).message);
    console.log("\n💡 Alternative solution: Create a new Safe account without registry hook");
    console.log("Run: ts-node scripts/create-safe-account-no-registry.ts");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error removing registry hook:", error);
    process.exit(1);
  });
