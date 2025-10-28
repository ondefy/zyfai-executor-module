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

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

async function main() {
  console.log("Starting comprehensive installation process using existing contracts...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  // const safeAddress = process.env.SAFE_ACCOUNT_ADDRESS;
  const targetRegistryAddress = process.env.TARGET_REGISTRY_ADDRESS;
  const guardedExecModuleAddress = process.env.GUARDED_EXEC_MODULE_ADDRESS;
  
  const eoaAccount = privateKeyToAccount(privateKey as `0x${string}`);
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
    
    // Create Safe account using toSafeSmartAccount with the SAME configuration as the existing one
    // This will generate the same address as the existing Safe account
    const safeAccount = await toSafeSmartAccount({
      client: publicClient,
      owners: [eoaAccount],
      version: '1.4.1',
      entryPoint: {
        address: entryPoint07Address,
        version: '0.7',
      },
      safe4337ModuleAddress: '0x7579EE8307284F293B1927136486880611F20002',
      erc7579LaunchpadAddress: '0x7579011aB74c46090561ea277Ba79D510c6C00ff',
      // attesters: [
      //   RHINESTONE_ATTESTER_ADDRESS, // Rhinestone Attester - SAME as original
      // ],
      // attestersThreshold: 1, // SAME as original
      validators: [
        {
          address: ownableValidator.address,
          context: ownableValidator.initData,
        },
      ],
      saltNonce: fromHex(toHex(process.env.ACCOUNT_SALT || '0x1'), 'bigint'), // SAME salt as original
    });

    const generatedSafeAddress = await safeAccount.getAddress();
    console.log("Generated Safe address:", generatedSafeAddress);
    
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
    
    // Use the existing deployed module address
    console.log("Installing module:", guardedExecModuleAddress);
    
    // Check if module is already installed
    try {
      const enabledModules = await publicClient.readContract({
        address: generatedSafeAddress as `0x${string}`,
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
      
      if (enabledModules.includes(guardedExecModuleAddress as `0x${string}`)) {
        console.log("Module already installed");
        return;
      }
    } catch (error) {
      console.log("⚠️ Could not check existing modules, proceeding with installation...");
    }
    
    console.log("Installing module using Safe's native installModule method...", guardedExecModuleAddress);
    
    // Install module using Safe's native installModule method
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
        guardedExecModuleAddress as `0x${string}`,
        '0x' // No initialization data needed
      ],
    });
    console.log("Install module data:", installModuleData);
    
    // Execute the installation transaction
    const transaction = await smartAccountClient.sendTransaction({
      to: generatedSafeAddress as `0x${string}`,
      value: 0n,
      data: installModuleData,
    });
    console.log("Transaction submitted:", transaction);
    
    // Wait for execution
    const result = await smartAccountClient.waitForUserOperationReceipt({
      hash: transaction,
    });
    console.log("Module installation completed:", result);
    
    // Verify installation
    try {
      const enabledModules = await publicClient.readContract({
        address: generatedSafeAddress as `0x${string}`,
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
      const isNowInstalled = enabledModules.includes(guardedExecModuleAddress as `0x${string}`);      
      if (isNowInstalled) {
        console.log("GuardedExecModule successfully installed and verified");
      } else {
        console.log("Module installation verification failed");
      }
    } catch (verifyError) {
      console.log("Could not verify installation, but transaction completed:", (verifyError as Error).message);
    }
    
  } catch (error) {
    console.error("Error installing module:", (error as Error).message);
    throw error;
  }
  
  console.log("\n Complete installation process finished successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error in installation:", error);
    process.exit(1);
  });
