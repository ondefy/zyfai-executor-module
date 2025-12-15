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
    
    const USDC_ADDRESS = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as `0x${string}`;
    const AAVE_POOL_ADDRESS = '0xA238Dd80C259a72e81d7e4664a9801593F98d1c5' as `0x${string}`;
    // Prepare encodeFunctionData for ERC20 approve
    const approveData = encodeFunctionData({
      abi: erc20Abi,
      functionName: 'approve',
      // args: ["0x3128a0F7f0ea68E7B7c9B00AFa7E41045828e858" as Address, BigInt(1_000_000)], // for Spark
      // args: ["0x1C4a802FD6B591BB71dAA01D8335e43719048B24" as Address, BigInt(1_000_000)], // for Wasabi
      // args: ["0xb125E6687d4313864e53df431d5425969c15Eb2F" as Address, BigInt(1_000_000)], // for Compound
      // args: ["0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22" as Address, BigInt(1_000_000)], // for Moonwell
      // args: ["0x90613e167D42CA420942082157B42AF6fc6a8087" as Address, BigInt(1_000_000)], // for Harvest
      // args: ["0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169", BigInt(1_000_000)], // for Fluid
      // args: ["0xB7890CEE6CF4792cdCC13489D36D9d42726ab863", BigInt(1_000_000)], // for Morpho
      // args: ["0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf", BigInt(1_000_000)], // for EnsoRouter
      args: [AAVE_POOL_ADDRESS as Address, BigInt(1_000_000)], // amount 0, you can set value as needed
    });

    // Encode transfer(address recipient,uint256 amount) for USDC
    // Example values:
    // - recipient: safeAccount.address (just as an example, could be another address)
    // - amount: 10000 (1 USDC in 6 decimals)
    const TRANSFER_AMOUNT = BigInt(100); // e.g., 0.01 USDC (6 decimals)
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
        "0xd61C43c089852e0AB68B967dD1eDe03a18e52223", // add your owner
        TRANSFER_AMOUNT
      ]
    });

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
    const WITHDRAW_AMOUNT = BigInt(1000); // 1 USDC (6 decimals)
    const withdrawData = encodeFunctionData({
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
      args: [
        USDC_ADDRESS,
        WITHDRAW_AMOUNT,
        safeAccount.address
      ]
    });

    // ERC4626 "deposit(uint256 assets, address receiver)" (see @data.ts)
    const ERC4626_DEPOSIT_AMOUNT = BigInt(10000); // e.g., 0.01 USDC (6 decimals)
    const ERC4626_DEPOSIT_DATA = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "uint256", "name": "assets", "type": "uint256" },
            { "internalType": "address", "name": "receiver", "type": "address" }
          ],
          "name": "deposit",
          "outputs": [
            { "internalType": "uint256", "name": "", "type": "uint256" }
          ],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'deposit',
      args: [
        ERC4626_DEPOSIT_AMOUNT, // assets
        "0x4D095Bc747846e1d189F1a2Fe75B0F42981Ed142", // receiver
      ]
    });

    const ERC4626_REDEEM_AMOUNT = BigInt(7682); // shares with decimals 18/6
    // ERC4626 "redeem(uint256 shares, address receiver, address owner)" (see @data.ts line 141-142)
    const ERC4626_REDEEM_DATA = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "uint256", "name": "shares", "type": "uint256" },
            { "internalType": "address", "name": "receiver", "type": "address" },
            { "internalType": "address", "name": "owner", "type": "address" }
          ],
          "name": "redeem",
          "outputs": [
            { "internalType": "uint256", "name": "", "type": "uint256" }
          ],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'redeem',
      args: [
        ERC4626_REDEEM_AMOUNT, // shares
        "0x4D095Bc747846e1d189F1a2Fe75B0F42981Ed142", // receiver
        "0x4D095Bc747846e1d189F1a2Fe75B0F42981Ed142", // owner
      ]
    });

    // Compound V3 "supply(address asset, uint256 amount)" (see @data.ts lines 129-130)
    const COMPOUND_V3_SUPPLY_AMOUNT = BigInt(2500); // for example, 0.0025 USDC (assuming 6 decimals)
    const COMPOUND_V3_SUPPLY_DATA = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "address", "name": "asset", "type": "address" },
            { "internalType": "uint256", "name": "amount", "type": "uint256" }
          ],
          "name": "supply",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'supply',
      args: [
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // USDC address
        COMPOUND_V3_SUPPLY_AMOUNT                   // amount
      ]
    });

    // Compound V3 "withdraw(address asset, uint256 amount)" (see @data.ts lines 130-131)
    const COMPOUND_V3_WITHDRAW_AMOUNT = BigInt(1400); // for example, 0.001 USDC (6 decimals)
    const COMPOUND_V3_WITHDRAW_DATA = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "address", "name": "asset", "type": "address" },
            { "internalType": "uint256", "name": "amount", "type": "uint256" }
          ],
          "name": "withdraw",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'withdraw',
      args: [
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // USDC address
        COMPOUND_V3_WITHDRAW_AMOUNT                 // amount
      ]
    });

    // Moonwell "mint(uint256 amount)" (see @data.ts lines 133-134)
    const MOONWELL_MINT_AMOUNT = BigInt(10000); // for example, 0.1 USDC (6 decimals)
    const MOONWELL_MINT_DATA = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "uint256", "name": "mintAmount", "type": "uint256" }
          ],
          "name": "mint",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'mint',
      args: [
        MOONWELL_MINT_AMOUNT
      ]
    });

    // Moonwell "redeem(uint256 redeemAmount)" (see @data.ts lines 134-135)
    const MOONWELL_REDEEM_AMOUNT = BigInt(44591932); // for example, 0.05 USDC (6 decimals)
    const MOONWELL_REDEEM_DATA = encodeFunctionData({
      abi: [
        {
          "inputs": [
            { "internalType": "uint256", "name": "redeemAmount", "type": "uint256" }
          ],
          "name": "redeem",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      functionName: 'redeem',
      args: [
        MOONWELL_REDEEM_AMOUNT
      ]
    });

    const executions = [
      {
        target: USDC_ADDRESS,
        value: BigInt(0),
        callData: approveData,
      },

      // {
      //   target: AAVE_POOL_ADDRESS,
      //   value: BigInt(0),
      //   callData: supplyData,
      // },
      // {
      //   target: AAVE_POOL_ADDRESS,
      //   value: BigInt(0),
      //   callData: withdrawData,
      // },

      // {
      //   target: "0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22",
      //   value: BigInt(0),
      //   callData: MOONWELL_MINT_DATA,
      // },
      // {
      //   target: "0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22",
      //   value: BigInt(0),
      //   callData: MOONWELL_REDEEM_DATA,
      // },

      // {
      //   target: "0xb125E6687d4313864e53df431d5425969c15Eb2F",
      //   value: BigInt(0),
      //   callData: COMPOUND_V3_SUPPLY_DATA,
      // },
      // {
      //   target: "0xb125E6687d4313864e53df431d5425969c15Eb2F",
      //   value: BigInt(0),
      //   callData: COMPOUND_V3_WITHDRAW_DATA,
      // },

      // {
      //   target: "0x90613e167D42CA420942082157B42AF6fc6a8087",
      //   value: BigInt(0),
      //   callData: ERC4626_DEPOSIT_DATA,
      // },
      // {
      //   target: "0x90613e167D42CA420942082157B42AF6fc6a8087",
      //   value: BigInt(0),
      //   callData: ERC4626_REDEEM_DATA,
      // },

      // {
      //   target: "0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf",
      //   value: BigInt(0),
      //   callData: "0xb94c3609000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000186a0000000000000000000000000000000000000000000000000000000000000140495352c9fad7c5bef027816a800da1736444fb58a807ef4c9603b7848673f7e3a68eb14a57bc81406ea5ffc6411f37f8e0b1b772e73406f4f263decaccaa9acbb33b20f2b000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000006a9059cbb010001ffffffffff833589fcd6edb6e08f4c7c32d4f71b54bda02913095ea7b3010203ffffffffff833589fcd6edb6e08f4c7c32d4f71b54bda02913346387bf410000000000000abedfac7488dccaafdd66d1d7d56349780fe0477e0404050603070008898affffffffffffffffffffffffffffffffffffffffffff6e7a43a3010a0bffffffff0a7e7d64d987cab6eed08a191c4c2459daf2f8ed0b241c5912010affffffffffff7e7d64d987cab6eed08a191c4c2459daf2f8ed0b000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000038000000000000000000000000000000000000000000000000000000000000003c00000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000124000000000000000000000000000000000000000000000000000000000000000200000000000000000000000004d095bc747846e1d189f1a2fe75b0f42981ed142000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000003e80000000000000000000000000000000000000000000000000000000000000020000000000000000000000000bedfac7488dccaafdd66d1d7d56349780fe0477e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000182b800000000000000000000000000000000000000000000000000000000000000200000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b50000000000000000000000000000000000000000000000000000000000000020000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000000000020000000000000000000000000fde4c96c8593536e31f229ea8f37b2ada2699bb20000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000001876b000000000000000000000000000000000000000000000000000000000000002000000000000000000000000069afa05352b3797b8d08ce3b5edf27eb0585d5600000000000000000000000000000000000000000000000000000000000000e200000000000000000000000000000000000000000000000000000000000000de4e21fd0e9000000000000000000000000000000000000000000000000000000000000002000000000000000000000000063242a4ea82847b20e506b63b0e2e2eff0cc6cb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000008c00000000000000000000000000000000000000000000000000000000000000b000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000182b8000000000000000000000000000182b8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000414969a86c21544acba07d7ce61432d25670c3e20e335c99bce3f03e11a58310f44501f73077d5dac1d4328e71ffb91c73887dbfc2e26fe6122df487b18abf75491c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000bedfac7488dccaafdd66d1d7d56349780fe0477e0000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000016f620000000000000000000000000001960e000000000000000000000000000182b80000000000000000000000000001876c00000000000000000000000000000000000000000000010000000f42400000000000000000000000000000004f82e73edb06d29ff62c91ec8f5ff06571bdeb29000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000029e8d6080000000000000000000000000000000000000000000000000000000000000006e0000000000000000000000000000000000000000000000000000000000000000161f598cd00000000000000002b8574f0f6ded2a4846d27350a909c355497d929000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000004c0000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291380000000000000000000000000000001000000000000000000000000000182b800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000182b8e2b7e77a00000000000100015455c918e405a2831fbff8595c0aae35ee3db9d1000000000000000000000000000000000000000000000000000000000000008000000000000000000000000063242a4ea82847b20e506b63b0e2e2eff0cc6cb0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000123d5103782389f305ec402961fa8d46875c49e4c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf80000000000000000000000000000001000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000070b372966800000000000000025455c918e405a2831fbff8595c0aae35ee3db9d1000000000000000000000000000000000000000000000000000000000000008000000000000000000000000063242a4ea82847b20e506b63b0e2e2eff0cc6cb000000000000000000000000000000000000000000000000000000000000000200000000300000000000003e84fe4a5f570b046e3704acd72fef6c508a310d3aa000000000000000000000000420000000000000000000000000000000000000680000000000000000000000001e87cf0000000000000000000001d1dbc6e148000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000001d1dbc6e148064a6873000000000000000030c3b706efa1da39450c968e669fdc442fc375021000000000000000000000000000000000000000000000000000000000000008000000000000000000000000063242a4ea82847b20e506b63b0e2e2eff0cc6cb00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000fbc155aeb7af7fc9d779b1c46d26bfd6e93854e1000000000000000000000000fde4c96c8593536e31f229ea8f37b2ada2699bb28000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000fde4c96c8593536e31f229ea8f37b2ada2699bb2000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000bedfac7488dccaafdd66d1d7d56349780fe0477e00000000000000000000000000000000000000000000000000000000000182b80000000000000000000000000000000000000000000000000000000000017bac00000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000000100000000000000000000000063242a4ea82847b20e506b63b0e2e2eff0cc6cb0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000182b800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002867b22536f75726365223a22456e736f2d656630366338613832313238222c22416d6f756e74496e555344223a22302e3039393033333832343430383532333738222c22416d6f756e744f7574555344223a22302e3130303131373039353332373239313137222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a22313030323033222c2254696d657374616d70223a313736353738333939342c22526f7574654944223a2236366661353562352d383830372d346234362d396538332d3832373135616636353563363a64623462333137312d346536632d343333382d396662302d343863643933353738303861222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a22647148764e412f6638474a48434b5773556c434e4b394a316a346c5a4e6477645139633373756842706f5937524f424f7a484977334749576a4151427a5a5635614737622b32665136366d705967714d4374594266734d58706a624e7a794d6c37374c42683467532f616530326b4e316b51476e72655356345146794b312f616a424d446d387864753964626a767571734774325a5a54556844713750525a3378505576534761493844575679504b6a4163594b596a3645416f52514944497632346a614d39314e6c42622b524d684d58324c542f6c657a53727a504752457177514f7871316131744d37527755444a5a445045306156415655366e356d4b597844577839546e584c746a5756484b554c44416e44386f485574456f36594864575832436d4d4748375376652b4d7143714561544270523336713976754f574f4d334646385a5a2b67336b30566b675349592f4a59413d3d227d7d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000017bac00000000000000000000000000000000000000000000000000000000",
      // },
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
