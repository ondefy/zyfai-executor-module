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
 * Schedule whitelist operation in TargetRegistry for AAVE withdraw
 * 
 * This script schedules adding AAVE Pool withdraw function to the whitelist (1 day timelock).
 * After scheduling, you need to wait 1 day and then use 7-execute-whitelist.ts to execute.
 * 
 * Target: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5 (AAVE Pool)
 * Function: withdraw(address asset,uint256 amount,address to)
 */
async function main() {
  console.log("Schedule AAVE Withdraw Whitelist");
  console.log("==================================\n");
  
  // Check environment variables    
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const registryAddress = process.env.TARGET_REGISTRY_ADDRESS;
  const rpcUrl = process.env.BASE_RPC_URL;
  
  // Static configuration: AAVE Pool withdraw
  const target = '0xA238Dd80C259a72e81d7e4664a9801593F98d1c5' as Address;
  const functionName = 'withdraw';
  
  console.log("Configuration:");
  console.log("  Registry address:", registryAddress);
  console.log("  RPC URL:", rpcUrl);
  console.log("  Target (AAVE Pool):", target);
  console.log("  Function: withdraw(address asset,uint256 amount,address to)");
  
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
  
  // TargetRegistry ABI
  const registryAbi = parseAbi([
    "function scheduleAdd(address target, bytes4 selector) external returns (bytes32 operationId)",
    "function scheduleRemove(address target, bytes4 selector) external returns (bytes32 operationId)",
    "function executeOperation(address target, bytes4 selector) external",
    "function cancelOperation(address target, bytes4 selector) external",
    "function isWhitelisted(address target, bytes4 selector) external view returns (bool)",
    "function isOperationReady(address target, bytes4 selector) external view returns (bool)",
    "function isOperationPending(address target, bytes4 selector) external view returns (bool)",
    "function getTimestamp(address target, bytes4 selector) external view returns (uint256)",
    "function getOperationId(address target, bytes4 selector) external view returns (bytes32)",
    "function whitelist(address, bytes4) external view returns (bool)",
    "event TargetSelectorScheduled(bytes32 indexed operationId, address indexed target, bytes4 indexed selector, uint256 executeAfter)",
    "event TargetSelectorAdded(address indexed target, bytes4 indexed selector)",
    "event TargetSelectorRemoved(address indexed target, bytes4 indexed selector)",
  ]);
  
  // Calculate selector for withdraw(address asset,uint256 amount,address to)
  let finalSelector: `0x${string}`;
  
  try {
    finalSelector = toFunctionSelector(
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
    console.log("\nCalculated selector:", finalSelector);
    console.log("  Function signature: withdraw(address,uint256,address)");
  } catch (error) {
    throw new Error(`Failed to calculate selector for withdraw function. Error: ${error}`);
  }
  
  try {
    // Check current whitelist status
    console.log("\nChecking current whitelist status...");
    const isWhitelisted = await publicClient.readContract({
      address: registryAddress as Address,
      abi: registryAbi,
      functionName: 'isWhitelisted',
      args: [target, finalSelector],
    });
    
    if (isWhitelisted) {
      console.log("Target+Selector is already whitelisted!");
      return;
    }
    
    console.log("Target+Selector is NOT whitelisted (proceeding...)");
    
    // Check if there's a pending operation
    console.log("\nChecking for pending operations...");
    const isPending = await publicClient.readContract({
      address: registryAddress as Address,
      abi: registryAbi,
      functionName: 'isOperationPending',
      args: [target, finalSelector],
    });
    
    if (isPending) {
      const timestamp = await publicClient.readContract({
        address: registryAddress as Address,
        abi: registryAbi,
        functionName: 'getTimestamp',
        args: [target, finalSelector],
      });
      
      const currentTimestamp = (await publicClient.getBlock({ blockTag: 'latest' })).timestamp;
      const remainingTime = Number(timestamp) - Number(currentTimestamp);
      
      console.log("Operation is already pending.");
      console.log("  Execute after timestamp:", timestamp.toString());
      console.log("  Current timestamp:", currentTimestamp.toString());
      
      if (remainingTime > 0) {
        console.log("  Remaining time:", remainingTime, "seconds");
        console.log("  Remaining time:", Math.floor(remainingTime / 3600), "hours");
        console.log("\nTo execute after timelock expires, run:");
        console.log(`   pnpm run execute-whitelist`);
      } else {
        console.log("  Timelock has expired! Ready to execute.");
        console.log("\nTo execute now, run:");
        console.log(`   pnpm run execute-whitelist`);
      }
      return;
    }
    
    // No pending operation, schedule a new one
    console.log("\nNo pending operation found. Scheduling new whitelist operation...");
    console.log("  Note: This operation will require a 1-day timelock before execution.");
    
    const scheduleHash = await walletClient.sendTransaction({
      to: registryAddress as Address,
      data: encodeFunctionData({
        abi: registryAbi,
        functionName: 'scheduleAdd',
        args: [target, finalSelector],
      }),
    });
    
    console.log("Transaction sent!");
    console.log("  Transaction hash:", scheduleHash);
    
    // Wait for confirmation
    console.log("\nWaiting for transaction confirmation...");
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: scheduleHash,
    });
    
    console.log("Transaction confirmed!");    
  } catch (error: any) {
    console.error("\nError:", error.message);
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
