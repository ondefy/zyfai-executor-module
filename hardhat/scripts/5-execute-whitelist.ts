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
} from 'viem';
import dotenv from "dotenv";
import { join } from "path";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Execute whitelist operation in TargetRegistry for AAVE withdraw
 * 
 * This script executes a scheduled AAVE Pool withdraw whitelist operation after the timelock expires.
 * Make sure the operation was scheduled at least 1 day ago using 6-whitelist-registry.ts.
 * 
 * Target: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5 (AAVE Pool)
 * Function: withdraw(address asset,uint256 amount,address to)
 */
async function main() {
  console.log("🚀 Execute AAVE Withdraw Whitelist");
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
  console.log("\n📝 Account address:", account.address);
  
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
    "function executeOperation(address target, bytes4 selector) external",
    "function isWhitelisted(address target, bytes4 selector) external view returns (bool)",
    "function isOperationReady(address target, bytes4 selector) external view returns (bool)",
    "function isOperationPending(address target, bytes4 selector) external view returns (bool)",
    "function getTimestamp(address target, bytes4 selector) external view returns (uint256)",
    "event TargetSelectorAdded(address indexed target, bytes4 indexed selector)",
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
    console.log("\n✅ Calculated selector:", finalSelector);
    console.log("  Function signature: withdraw(address,uint256,address)");
  } catch (error) {
    throw new Error(`Failed to calculate selector for withdraw function. Error: ${error}`);
  }
  
  try {
    // Check if already whitelisted
    console.log("\n🔍 Checking whitelist status...");
    const isWhitelisted = await publicClient.readContract({
      address: registryAddress as Address,
      abi: registryAbi,
      functionName: 'isWhitelisted',
      args: [target, finalSelector],
    });
    
    if (isWhitelisted) {
      console.log("✅ Target+Selector is already whitelisted!");
      console.log("  No need to execute.");
      return;
    }
    
    // Check if operation is pending
    console.log("\n🔍 Checking operation status...");
    const isPending = await publicClient.readContract({
      address: registryAddress as Address,
      abi: registryAbi,
      functionName: 'isOperationPending',
      args: [target, finalSelector],
    });
    
    if (!isPending) {
      console.log("⚠️  No pending operation found for AAVE Pool withdraw.");
      console.log("  Please schedule the operation first using: pnpm run whitelist-registry");
      return;
    }
    
    // Check if operation is ready
    const isReady = await publicClient.readContract({
      address: registryAddress as Address,
      abi: registryAbi,
      functionName: 'isOperationReady',
      args: [target, finalSelector],
    });
    
    if (!isReady) {
      const timestamp = await publicClient.readContract({
        address: registryAddress as Address,
        abi: registryAbi,
        functionName: 'getTimestamp',
        args: [target, finalSelector],
      });
      
      const currentTimestamp = (await publicClient.getBlock({ blockTag: 'latest' })).timestamp;
      const remainingTime = Number(timestamp) - Number(currentTimestamp);
      
      console.log("⏰ Operation is not ready yet.");
      console.log("  Execute after timestamp:", timestamp.toString());
      console.log("  Current timestamp:", currentTimestamp.toString());
      console.log("  Remaining time:", remainingTime, "seconds");
      console.log("  Remaining time:", Math.floor(remainingTime / 3600), "hours");
      
      if (remainingTime > 0) {
        console.log("\n💡 Please wait for the timelock to expire before executing.");
      }
      return;
    }
    
    console.log("✅ Operation is ready to execute!");
    
    // Execute the operation
    console.log("\n🚀 Executing operation...");
    const executeHash = await walletClient.sendTransaction({
      to: registryAddress as Address,
      data: encodeFunctionData({
        abi: registryAbi,
        functionName: 'executeOperation',
        args: [target, finalSelector],
      }),
    });
    
    console.log("✅ Transaction sent!");
    console.log("  Transaction hash:", executeHash);
    
    // Wait for confirmation
    console.log("\n⏳ Waiting for confirmation...");
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: executeHash,
    });
    
    console.log("✅ Operation executed successfully!");
    console.log("  Block number:", receipt.blockNumber.toString());
    console.log("  Gas used:", receipt.gasUsed.toString());
    
    // Verify it's whitelisted now
    const nowWhitelisted = await publicClient.readContract({
      address: registryAddress as Address,
      abi: registryAbi,
      functionName: 'isWhitelisted',
      args: [target, finalSelector],
    });
    
    if (nowWhitelisted) {
      console.log("\n✅✅ Target+Selector is now whitelisted!");
    } else {
      console.log("\n⚠️  Warning: Operation executed but target+selector is still not whitelisted");
      console.log("  Check transaction receipt for errors.");
    }
    
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
    console.log("\n✅ Script completed successfully!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ Fatal error:", error);
    process.exit(1);
  });
