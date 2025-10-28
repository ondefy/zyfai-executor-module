import { getAccountNonce } from 'permissionless/actions';
import { createSmartAccountClient } from 'permissionless';
import { toSafeSmartAccount } from 'permissionless/accounts';
import { erc7579Actions } from 'permissionless/actions/erc7579';
import { createPimlicoClient } from 'permissionless/clients/pimlico';
import { 
  getSmartSessionsValidator,
  OWNABLE_VALIDATOR_ADDRESS,
  getSudoPolicy,
  Session,
  getAccount,
  encodeSmartSessionSignature,
  getOwnableValidatorMockSignature,
  RHINESTONE_ATTESTER_ADDRESS,
  encodeValidatorNonce,
  getOwnableValidator,
  encodeValidationData,
  getEnableSessionDetails,
} from '@rhinestone/module-sdk';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { 
  toHex,
  Address,
  Hex,
  createPublicClient,
  http,
  toBytes,
  erc20Abi,
  prepareEncodeFunctionData,
  encodeFunctionData,
} from 'viem';
import {
  entryPoint07Address,
  getUserOperationHash,
  createPaymasterClient,
} from 'viem/account-abstraction';
import { toFunctionSelector, getAbiItem } from 'viem';
import dotenv from "dotenv";
import { join } from "path";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Create session key with sudo policy for USDC approve
 * 
 * Follows Rhinestone module-sdk docs pattern using permissionless.js:
 * 1. Install Smart Sessions Module (if not installed)
 * 2. Create session with sudo policy
 * 3. Link session to USDC contract (via action targeting approve function)
 * 4. Enable session on the Safe account
 */
async function main() {
  console.log("🔑 Creating session key with sudo policy for USDC approve...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const safeAddress = process.env.SAFE_ACCOUNT_ADDRESS;
  const rpcUrl = process.env.BASE_RPC_URL;
  
  // USDC contract address on Base
  const usdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as Address;
  const aavePoolAddress = '0xA238Dd80C259a72e81d7e4664a9801593F98d1c5' as `0x${string}`;
  
  console.log("Configuration:");
  console.log("  Safe address:", safeAddress);
  console.log("  AAVE Pool address:", aavePoolAddress);
  console.log("  RPC URL:", rpcUrl);
  
  if (!privateKey || !safeAddress || !rpcUrl) {
    throw new Error("Missing required environment variables");
  }
  
  // Create account from private key
  const owner = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("\nOwner account address:", owner.address);
  
  // Generate session key (or use existing from env)
  let sessionKeyPrivateKey = process.env.SESSION_KEY_PRIVATE_KEY;
  let sessionOwner;
  
  if (sessionKeyPrivateKey) {
    sessionOwner = privateKeyToAccount(sessionKeyPrivateKey as `0x${string}`);
    console.log("\nUsing existing session key:");
  } else {
    sessionKeyPrivateKey = generatePrivateKey();
    sessionOwner = privateKeyToAccount(sessionKeyPrivateKey as `0x${string}`);
    console.log("\nGenerated new session key:");
  }
  
  console.log("  Session key address:", sessionOwner.address);
  console.log("  Session key private key:", sessionKeyPrivateKey);
  
  try {
    // Create clients (same pattern as script 2)
    const publicClient = createPublicClient({
      transport: http(rpcUrl),
      chain: base,
    });
    
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
    
    const paymasterClient = createPaymasterClient({
      transport: http(pimlicoUrl),
    });
    
    // Create ownable validator for Safe account
    const ownableValidator = getOwnableValidator({
      owners: [owner.address],
      threshold: 1,
    });
    
    // Create Smart Account instance from existing Safe
    console.log("\nLoading existing Safe account...");
    const safeAccount = await toSafeSmartAccount({
      client: publicClient,
      owners: [owner],
      version: '1.4.1',
      entryPoint: {
        address: entryPoint07Address,
        version: '0.7',
      },
      safe4337ModuleAddress: '0x7579EE8307284F293B1927136486880611F20002',
      erc7579LaunchpadAddress: '0x7579011aB74c46090561ea277Ba79D510c6C00ff',
      attesters: [
        RHINESTONE_ATTESTER_ADDRESS,
      ],
      attestersThreshold: 1,
      address: safeAddress as `0x${string}`,
      validators: [
        {
          address: ownableValidator.address,
          context: ownableValidator.initData,
        },
      ],
    });
    
    const loadedSafeAddress = await safeAccount.getAddress();
    console.log("Safe account loaded:", loadedSafeAddress);
    
    // Create smart account client
    // @ts-ignore - Type compatibility between permissionless versions
    const smartAccountClient = createSmartAccountClient({
      account: safeAccount,
      chain: base,
      bundlerTransport: http(pimlicoUrl),
      paymaster: paymasterClient,
      userOperation: {
        estimateFeesPerGas: async () => {
          return (await pimlicoClient.getUserOperationGasPrice()).fast;
        },
      },
    }).extend(erc7579Actions());
    
    // Install Smart Sessions Module if not already installed
    console.log("\nChecking if Smart Sessions Module is installed...");
    const smartSessions = getSmartSessionsValidator({});
    
    try {
      const isInstalled = await smartAccountClient.isModuleInstalled({
        address: smartSessions.address as `0x${string}`,
        type: 'validator',
        context: '0x',
      });
      
      if (!isInstalled) {
        console.log("Installing Smart Sessions Module...");
        const opHash = await smartAccountClient.installModule({
          address: smartSessions.address as `0x${string}`,
          type: 'validator',
          context: '0x',
        });
        
        await pimlicoClient.waitForUserOperationReceipt({
          hash: opHash,
        });
        console.log("Smart Sessions Module installed!");
      } else {
        console.log("Smart Sessions Module already installed");
      }
    } catch (error) {
      console.log("Could not check Smart Sessions module, attempting installation...");
      try {
        const opHash = await smartAccountClient.installModule({
          address: smartSessions.address as `0x${string}`,
          type: 'validator',
          context: '0x',
        });
        await pimlicoClient.waitForUserOperationReceipt({ hash: opHash });
        console.log("Smart Sessions Module installed!");
      } catch (installError) {
        console.log("Installation check failed, continuing...");
      }
    }

    const withdrawSelector = toFunctionSelector(
      getAbiItem({
        abi: [
          {
            name: 'withdraw',
            type: 'function',
            inputs: [
              { name: 'asset', type: 'address' },
              { name: 'amount', type: 'uint256' },
              { name: 'to', type: 'address' }
            ],
            outputs: [],
            stateMutability: 'nonpayable',
          }
        ],
        name: 'withdraw',
      })
    ) as Hex;
    
    console.log("\nCreating session configuration...");
    console.log("  Target (AAVE Pool):", aavePoolAddress);
    console.log("  Selector (withdraw):", withdrawSelector);
    console.log("  Policy: Sudo (allows all operations)");
    
    // Create the session to enable
    const session: Session = {
      sessionValidator: OWNABLE_VALIDATOR_ADDRESS,
      sessionValidatorInitData: encodeValidationData({
        threshold: 1,
        owners: [sessionOwner.address],
      }),
      salt: toHex(toBytes('0', { size: 32 })),
      userOpPolicies: [getSudoPolicy()],
      erc7739Policies: {
        allowedERC7739Content: [],
        erc1271Policies: [],
      },
      actions: [
        {
          actionTarget: aavePoolAddress, // USDC contract address
          actionTargetSelector: withdrawSelector, // approve function selector
          actionPolicies: [getSudoPolicy()],
        },
      ],
      chainId: BigInt(base.id),
      permitERC4337Paymaster: true,
    };
    
    console.log("Session configuration created");
    
    // Get session details for enabling
    console.log("\nGetting session enable details...");
    const account = getAccount({
      address: safeAccount.address,
      type: 'safe',
    });
    
    // @ts-ignore - Type compatibility between viem versions
    const sessionDetails = await getEnableSessionDetails({
      sessions: [session],
      account,
      clients: [publicClient] as any,
    });
    
    console.log("Session details generated");
    
    // Have the user sign the enable signature
    console.log("\nSigning permission enable hash...");
    sessionDetails.enableSessionData.enableSession.permissionEnableSig =
      await owner.signMessage({
        message: { raw: sessionDetails.permissionEnableHash },
      });
    
    console.log("Permission enable signature created");
    
    // For enabling the session, we'll use the "enable mode" pattern from docs
    // This enables and executes in one transaction
    // Get nonce for Smart Sessions validator (required for enable mode)
    console.log("\nGetting nonce for Smart Sessions validator...");
    const nonce = await getAccountNonce(publicClient, {
      address: safeAccount.address,
      entryPointAddress: entryPoint07Address,
      key: encodeValidatorNonce({
        account,
        validator: smartSessions,
      }),
    });
    
    console.log("  Nonce:", nonce.toString());
    
    // Set mock signature for preparing UserOperation (will be replaced)
    sessionDetails.signature = getOwnableValidatorMockSignature({
      threshold: 1,
    });
    
    // Create UserOperation to enable the session
    // Following docs: call the session action target with enable mode signature
    console.log("\nCreating UserOperation to enable session...");
    console.log("  Action Target:", session.actions[0].actionTarget);
    console.log("  Action Selector:", session.actions[0].actionTargetSelector);
    console.log("  Using enable mode (enable + execute in one transaction)");

    // Prepare encodeFunctionData for withdraw(address asset, uint256 amount, address to)
    const withdraw = prepareEncodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "address", "name": "asset", "type": "address" },
            { "internalType": "uint256", "name": "amount", "type": "uint256" },
            { "internalType": "address", "name": "to", "type": "address" }
          ],
          "name": "withdraw",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'withdraw',
    });

    // @ts-ignore - Type compatibility
    const userOperation = await smartAccountClient.prepareUserOperation({
      account: safeAccount,
      calls: [
        {
          to: session.actions[0].actionTarget,
          value: BigInt(0),
          data: encodeFunctionData({
            ...withdraw,
            args: [usdcAddress, 1000n, safeAccount.address],
          }),
        },
      ],
      nonce,
      signature: encodeSmartSessionSignature(sessionDetails),
    });
    
    console.log("UserOperation prepared");
    
    // Sign UserOperation hash with session key (for enable mode)
    console.log("\nSigning UserOperation with session key...");
    const userOpHashToSign = getUserOperationHash({
      chainId: base.id,
      entryPointAddress: entryPoint07Address,
      entryPointVersion: '0.7',
      userOperation,
    });
    
    sessionDetails.signature = await sessionOwner.signMessage({
      message: { raw: userOpHashToSign },
    });
    
    userOperation.signature = encodeSmartSessionSignature(sessionDetails);
    
    console.log("Session key signature created");
    
    // Execute the UserOperation
    console.log("\nExecuting UserOperation to enable session...");
    const userOpHash = await smartAccountClient.sendUserOperation(userOperation);
    
    console.log("UserOperation submitted!");
    console.log("  UserOperation hash:", userOpHash);
    
    // Wait for receipt
    console.log("\nWaiting for confirmation...");
    const receipt = await pimlicoClient.waitForUserOperationReceipt({
      hash: userOpHash,
    });
    
    console.log("Session enabled successfully!");
    console.log("  Transaction hash:", receipt.receipt.transactionHash);
  } catch (error) {
    console.error("\nSession key creation failed:");
    console.error((error as Error).message);
    if ((error as any).stack) {
      console.error((error as any).stack);
    }
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });
