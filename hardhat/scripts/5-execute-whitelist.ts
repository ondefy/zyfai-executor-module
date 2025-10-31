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
 * Execute batch whitelist operations in TargetRegistry
 * 
 * This script executes scheduled whitelist operations after the timelock expires:
 * - AAVE Pool: supply(), withdraw()
 * - USDC: approve(), transfer()
 * 
 * Make sure operations were scheduled at least 1 day ago using 4-whitelist-registry.ts.
 * 
 * Targets:
 * - AAVE Pool: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
 * - USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
 */
async function main() {
  console.log("🚀 Execute Batch Whitelist Operations");
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
  
  // TargetRegistry ABI (updated for batch operations)
  const registryAbi = parseAbi([
    // Batch operations
    "function executeOperation(address[] calldata targets, bytes4[] calldata selectors) external",
    "function isWhitelisted(address target, bytes4 selector) external view returns (bool)",
    "function isOperationReady(address target, bytes4 selector) external view returns (bool)",
    "function isOperationPending(address target, bytes4 selector) external view returns (bool)",
    "function getTimestamp(address target, bytes4 selector) external view returns (uint256)",
    "event TargetSelectorAdded(address indexed target, bytes4 indexed selector)",
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
    // Prepare batch arrays for whitelist execution
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
    
    console.log("\n📋 Batch Whitelist Execution:");
    console.log("  1. AAVE Pool supply()");
    console.log("  2. AAVE Pool withdraw()");
    console.log("  3. USDC approve()");
    console.log("  4. USDC transfer()");
    
    // Check if any operations are pending
    console.log("\n🔍 Checking operation status...");
    let hasPending = false;
    for (let i = 0; i < targets.length; i++) {
      const isPending = await publicClient.readContract({
        address: registryAddress as Address,
        abi: registryAbi,
        functionName: 'isOperationPending',
        args: [targets[i], selectors[i]],
      });
      
      if (isPending) {
        hasPending = true;
        
        // Check if ready
        const isReady = await publicClient.readContract({
          address: registryAddress as Address,
          abi: registryAbi,
          functionName: 'isOperationReady',
          args: [targets[i], selectors[i]],
        });
        
        if (!isReady) {
          const timestamp = await publicClient.readContract({
            address: registryAddress as Address,
            abi: registryAbi,
            functionName: 'getTimestamp',
            args: [targets[i], selectors[i]],
          });
          
          const currentTimestamp = (await publicClient.getBlock({ blockTag: 'latest' })).timestamp;
          const remainingTime = Number(timestamp) - Number(currentTimestamp);
          
          console.log(`⏰ Operation ${i + 1} not ready yet.`);
          console.log(`  Remaining time: ${Math.floor(remainingTime / 3600)} hours`);
          
          if (remainingTime > 0) {
            console.log("\n💡 Please wait for timelock to expire before executing.");
            return;
          }
        }
      }
    }
    
    if (!hasPending) {
      console.log("⚠️  No pending operations found.");
      console.log("  Please schedule operations first using: pnpm run whitelist-registry");
      return;
    }
    
    console.log("✅ All operations are ready to execute!");
    
    // Execute all operations in batch
    console.log("\n🚀 Executing batch operations...");
    const executeHash = await walletClient.sendTransaction({
      to: registryAddress as Address,
      data: encodeFunctionData({
        abi: registryAbi,
        functionName: 'executeOperation',
        args: [targets, selectors],
      }),
    });
    
    console.log("✅ Transaction sent!");
    console.log("  Transaction hash:", executeHash);
    
    // Wait for confirmation
    console.log("\n⏳ Waiting for confirmation...");
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: executeHash,
    });
    
    console.log("✅ Batch operations executed successfully!");
    console.log("  Block number:", receipt.blockNumber.toString());
    console.log("  Gas used:", receipt.gasUsed.toString());
    
    // Verify all are whitelisted now
    console.log("\n✅ Verifying whitelist status...");
    for (let i = 0; i < targets.length; i++) {
      const nowWhitelisted = await publicClient.readContract({
        address: registryAddress as Address,
        abi: registryAbi,
        functionName: 'isWhitelisted',
        args: [targets[i], selectors[i]],
      });
      
      const opName = ['AAVE supply', 'AAVE withdraw', 'USDC approve', 'USDC transfer'][i];
      if (nowWhitelisted) {
        console.log(`  ✅ ${opName}: whitelisted`);
      } else {
        console.log(`  ⚠️  ${opName}: NOT whitelisted (check transaction)`);
      }
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
