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
  const guardedExecModuleAddress = process.env.GUARDED_EXEC_MODULE_UPGRADEABLE_ADDRESS;
  
  console.log("Configuration:");
  console.log("  Safe address:", safeAddress);
  console.log("  Guarded Exec Module address:", guardedExecModuleAddress);
  console.log("  RPC URL:", rpcUrl);
  
  if (!privateKey || !safeAddress || !rpcUrl || !guardedExecModuleAddress) {
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
    
    // Get function selector for executeGuardedBatch(Execution[] calldata executions)
    // Execution struct: { address target; uint256 value; bytes callData; }
    const executeGuardedBatchSelector = toFunctionSelector(
      getAbiItem({
        abi: [
          {
            name: "executeGuardedBatch",
            type: "function",
            inputs: [
              {
                name: "executions",
                type: "tuple[]",
                components: [
                  { name: "target", type: "address" },
                  { name: "value", type: "uint256" },
                  { name: "callData", type: "bytes" }
                ]
              }
            ],
            outputs: [],
            stateMutability: "nonpayable"
          }
        ],
        name: "executeGuardedBatch"
      })
    ) as Hex;
    
    console.log("\nCreating session configuration...");
    console.log("  Target (Guarded Exec Module):", guardedExecModuleAddress);
    console.log("  Selector (executeGuardedBatchSelector):", executeGuardedBatchSelector);
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
          actionTarget: guardedExecModuleAddress as `0x${string}`, // Guarded Exec Module address
          actionTargetSelector: executeGuardedBatchSelector, // function selector to be used in the execution, in this case no function selector is used
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
    

    const USDC_ADDRESS = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as `0x${string}`;
    const AAVE_POOL_ADDRESS = '0xA238Dd80C259a72e81d7e4664a9801593F98d1c5' as `0x${string}`;
    // Prepare encodeFunctionData for ERC20 approve
    const approveData = encodeFunctionData({
      abi: erc20Abi,
      functionName: 'approve',
      args: [AAVE_POOL_ADDRESS as Address, BigInt(1_000_000)], // amount 0, you can set value as needed
    });

    // GuardedExecModuleUpgradeable ABI for executeGuardedBatch
    // Execution struct: { address target; uint256 value; bytes callData; }
    const guardedExecModuleAbi = [
      {
        "inputs": [
          {
            "internalType": "tuple[]",
            "name": "executions",
            "type": "tuple[]",
            "components": [
              { "internalType": "address", "name": "target", "type": "address" },
              { "internalType": "uint256", "name": "value", "type": "uint256" },
              { "internalType": "bytes", "name": "callData", "type": "bytes" }
            ]
          }
        ],
        "name": "executeGuardedBatch",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      }
    ];

    // Prepare data for executeGuardedBatch with USDC (approve) and AAVE (supply)

    // supply(address asset,uint256 amount,address onBehalfOf,uint16 referralCode)
    // Example values for supply:
    // - asset: USDC address (same as above)
    // - amount: 1 USDC (but USDC is 6 decimals, so 1e6 = 1000000)
    // - onBehalfOf: safeAccount.address
    // - referralCode: 0
    const SUPPLY_AMOUNT = BigInt(1000); // 1 USDC (6 decimals)
    const supplyData = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "address", "name": "asset", "type": "address" },
            { "internalType": "uint256", "name": "amount", "type": "uint256" },
            { "internalType": "address", "name": "onBehalfOf", "type": "address" },
            { "internalType": "uint16", "name": "referralCode", "type": "uint16" }
          ],
          "name": "supply",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'supply',
      args: [
        USDC_ADDRESS,
        SUPPLY_AMOUNT,
        safeAccount.address,
        0
      ]
    });
    
    // Encode withdraw(address asset,uint256 amount,address to) for USDC
    // Example values:
    // - asset: USDC address (same as above)
    // - amount: 1 USDC (6 decimals, so 1e6 = 1000000)
    // - to: safeAccount.address
    // const WITHDRAW_AMOUNT = BigInt(10000); // 1 USDC (6 decimals)
    // const withdrawData = encodeFunctionData({
    //   abi: [
    //     {
    //       "inputs": [
    //         { "internalType": "address", "name": "asset", "type": "address" },
    //         { "internalType": "uint256", "name": "amount", "type": "uint256" },
    //         { "internalType": "address", "name": "to", "type": "address" }
    //       ],
    //       "name": "withdraw",
    //       "outputs": [],
    //       "stateMutability": "nonpayable",
    //       "type": "function"
    //     }
    //   ],
    //   functionName: 'withdraw',
    //   args: [
    //     USDC_ADDRESS,
    //     WITHDRAW_AMOUNT,
    //     safeAccount.address
    //   ]
    // });

    // Encode transfer(address recipient,uint256 amount) for USDC
    // Example values:
    // - recipient: safeAccount.address (just as an example, could be another address)
    // - amount: 10000 (1 USDC in 6 decimals)
    const TRANSFER_AMOUNT = BigInt(1000); // e.g., 0.01 USDC (6 decimals)
    const transferData = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "address", "name": "recipient", "type": "address" },
            { "internalType": "uint256", "name": "amount", "type": "uint256" }
          ],
          "name": "transfer",
          "outputs": [
            { "internalType": "bool", "name": "", "type": "bool" }
          ],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'transfer',
      args: [
        // "0xbA2aaF97D76dBF4dC9B9779683A22f5Ed4F23BcA", //mmalicious
        "0xd61C43c089852e0AB68B967dD1eDe03a18e52223",
        TRANSFER_AMOUNT
      ]
    });

    // Prepare data for executeGuardedBatch using Execution[] struct
    // Execution struct: { address target; uint256 value; bytes callData; }
    const executions = [
      {
        target: USDC_ADDRESS,
        value: BigInt(0),
        callData: approveData,
      },
      {
        target: AAVE_POOL_ADDRESS,
        value: BigInt(0),
        callData: supplyData,
      },
    ];

    const guardedExecCallData = encodeFunctionData({
      abi: guardedExecModuleAbi,
      functionName: 'executeGuardedBatch',
      args: [executions]
    });

    // @ts-ignore - Type compatibility
    const userOperation = await smartAccountClient.prepareUserOperation({
      account: safeAccount,
      calls: [
        {
          to: guardedExecModuleAddress,
          value: BigInt(0),
          data: guardedExecCallData,
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
