import { privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { 
  createPublicClient,
  createWalletClient,
  http, 
  Address,
  encodeFunctionData,
  parseAbi,
  toFunctionSelector,
  getAbiItem,
  decodeEventLog,
} from 'viem';
import dotenv from "dotenv";
import { join } from "path";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Schedule whitelist operations in TargetRegistry (BATCH)
 * 
 * This script schedules adding multiple functions to the whitelist (1 day timelock):
 * - AAVE Pool: supply(), withdraw()
 * - USDC: approve(), transfer()
 * - Also adds USDC to allowedERC20Tokens
 * 
 * After scheduling, wait 1 day and use 5-execute-whitelist.ts to execute.
 * 
 * Targets:
 * - AAVE Pool: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
 * - USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
 */
async function main() {
  console.log("Schedule Batch Whitelist Operations");
  console.log("==================================\n");
  
  // Check environment variables    
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const registryAddress = process.env.TARGET_REGISTRY_ADDRESS;
  const rpcUrl = process.env.BASE_RPC_URL;
  
  // Contract addresses
  const AAVE_POOL_ADDRESS = '0xA238Dd80C259a72e81d7e4664a9801593F98d1c5' as Address;
  const USDC_ADDRESS = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as Address;
  
  console.log("Configuration:");
  console.log("  Registry address:", registryAddress);
  console.log("  RPC URL:", rpcUrl);
  
  if (!privateKey || !registryAddress || !rpcUrl) {
    throw new Error("Missing required environment variables: BASE_PRIVATE_KEY, TARGET_REGISTRY_ADDRESS, BASE_RPC_URL");
  }
  
  // Create account from private key
  const account = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("\nAccount address:", account.address);
  
  // Create public client
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl),
  });
  
  // Create wallet client for sending transactions
  const walletClient = createWalletClient({
    account,
    chain: base,
    transport: http(rpcUrl),
  });
  
  // TargetRegistry ABI (updated for batch operations)
  const registryAbi = parseAbi([
    // Batch operations
    "function scheduleAdd(address[] memory targets, bytes4[] memory selectors) external returns (bytes32[] memory operationIds)",
    "function scheduleRemove(address[] memory targets, bytes4[] memory selectors) external returns (bytes32[] memory operationIds)",
    "function executeOperation(address[] memory targets, bytes4[] memory selectors) external",
    "function cancelOperation(address[] memory targets, bytes4[] memory selectors) external",
    // ERC20 operations
    "function addAllowedERC20Token(address[] memory tokens) external",
    "function removeAllowedERC20Token(address[] memory tokens) external",
    "function addAllowedERC20TokenRecipient(address token, address[] memory recipients) external",
    "function removeAllowedERC20TokenRecipient(address token, address[] memory recipients) external",
    // View functions
    "function isWhitelisted(address target, bytes4 selector) external view returns (bool)",
    "function isOperationReady(address target, bytes4 selector) external view returns (bool)",
    "function isOperationPending(address target, bytes4 selector) external view returns (bool)",
    "function getTimestamp(address target, bytes4 selector) external view returns (uint256)",
    "function getOperationId(address target, bytes4 selector) external view returns (bytes32)",
    "event TargetSelectorScheduled(bytes32 indexed operationId, address indexed target, bytes4 indexed selector, uint256 executeAfter)",
    "event TargetSelectorAdded(address indexed target, bytes4 indexed selector)",
    "event TargetSelectorRemoved(address indexed target, bytes4 indexed selector)",
  ]);
  
  // Calculate selectors for all functions
  let withdrawSelector: `0x${string}`;
  let supplySelector: `0x${string}`;
  let approveSelector: `0x${string}`;
  let transferSelector: `0x${string}`;
  
  try {
    // AAVE withdraw: withdraw(address asset,uint256 amount,address to)
    withdrawSelector = toFunctionSelector(
      getAbiItem({
        abi: [{
          name: 'withdraw',
          type: 'function',
          inputs: [
            { name: 'asset', type: 'address' },
            { name: 'amount', type: 'uint256' },
            { name: 'to', type: 'address' }
          ],
          outputs: [],
          stateMutability: 'nonpayable',
        }],
        name: 'withdraw',
      })
    );
    
    // AAVE supply: supply(address asset,uint256 amount,address onBehalfOf,uint16 referralCode)
    supplySelector = toFunctionSelector(
      getAbiItem({
        abi: [{
          name: 'supply',
          type: 'function',
          inputs: [
            { name: 'asset', type: 'address' },
            { name: 'amount', type: 'uint256' },
            { name: 'onBehalfOf', type: 'address' },
            { name: 'referralCode', type: 'uint16' }
          ],
          outputs: [],
          stateMutability: 'nonpayable',
        }],
        name: 'supply',
      })
    );
    
    // USDC approve: approve(address spender,uint256 amount)
    approveSelector = toFunctionSelector(
      getAbiItem({
        abi: [{
          name: 'approve',
          type: 'function',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' }
          ],
          outputs: [{ name: '', type: 'bool' }],
          stateMutability: 'nonpayable',
        }],
        name: 'approve',
      })
    );
    
    // USDC transfer: transfer(address to,uint256 amount)
    transferSelector = toFunctionSelector(
      getAbiItem({
        abi: [{
          name: 'transfer',
          type: 'function',
          inputs: [
            { name: 'to', type: 'address' },
            { name: 'amount', type: 'uint256' }
          ],
          outputs: [{ name: '', type: 'bool' }],
          stateMutability: 'nonpayable',
        }],
        name: 'transfer',
      })
    );
    
    console.log("\n✅ Calculated selectors:");
    console.log("  AAVE Pool supply():", supplySelector);
    console.log("  AAVE Pool withdraw():", withdrawSelector);
    console.log("  USDC approve():", approveSelector);
    console.log("  USDC transfer():", transferSelector);
  } catch (error) {
    throw new Error(`Failed to calculate selectors. Error: ${error}`);
  }
  
  try {
    // Prepare batch arrays for whitelist scheduling
    const targets = [
      AAVE_POOL_ADDRESS, // supply
      AAVE_POOL_ADDRESS, // withdraw
      USDC_ADDRESS,      // approve
      USDC_ADDRESS,      // transfer
    ];
    const selectors = [
      supplySelector,
      withdrawSelector,
      approveSelector,
      transferSelector,
    ];
    
    console.log("\n📋 Batch Whitelist Schedule:");
    console.log("  1. AAVE Pool supply()");
    console.log("  2. AAVE Pool withdraw()");
    console.log("  3. USDC approve()");
    console.log("  4. USDC transfer()");
    
    // Step 1: Schedule batch whitelist operations
    console.log("\n🚀 Step 1: Scheduling batch whitelist operations...");
    const scheduleHash = await walletClient.sendTransaction({
      to: registryAddress as Address,
      data: encodeFunctionData({
        abi: registryAbi,
        functionName: 'scheduleAdd',
        args: [targets, selectors],
      }),
    });
    
    console.log("✅ Transaction sent!");
    console.log("  Transaction hash:", scheduleHash);
    
    // Wait for confirmation
    console.log("\n⏳ Waiting for transaction confirmation...");
    const scheduleReceipt = await publicClient.waitForTransactionReceipt({
      hash: scheduleHash,
    });
    console.log("✅ Transaction confirmed!");
    
    // Step 2: Add USDC to allowedERC20Tokens (no timelock, executes immediately)
    console.log("\n🚀 Step 2: Adding USDC to allowedERC20Tokens...");
    const addTokenHash = await walletClient.sendTransaction({
      to: registryAddress as Address,
      data: encodeFunctionData({
        abi: registryAbi,
        functionName: 'addAllowedERC20Token',
        args: [[USDC_ADDRESS]],
      }),
    });
    
    console.log("✅ Transaction sent!");
    console.log("  Transaction hash:", addTokenHash);
    
    // Wait for confirmation
    console.log("\n⏳ Waiting for transaction confirmation...");
    const addTokenReceipt = await publicClient.waitForTransactionReceipt({
      hash: addTokenHash,
    });
    console.log("✅ USDC added to allowedERC20Tokens!");
    
    console.log("\n✅✅ Batch Whitelist Setup Complete!");
    console.log("\n⏰ Next Steps:");
    console.log("  - Wait 1 day for whitelist operations to be ready");
    console.log("  - Run: pnpm run execute-whitelist");
    
  } catch (error: any) {
    console.error("\n❌ Error:", error.message);
    if (error.shortMessage) {
      console.error("  Short message:", error.shortMessage);
    }
    if (error.data) {
      console.error("  Error data:", error.data);
    }
    throw error;
  }
}

main()
  .then(() => {
    console.log("\nScript completed successfully!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\nFatal error:", error);
    process.exit(1);
  });
