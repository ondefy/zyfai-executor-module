/**
 * Add Targets and Selectors to Whitelist
 * 
 * This script adds target+selector combinations to the TargetRegistry whitelist.
 * 
 * USAGE:
 * 1. Edit hardhat/scripts/whitelist/data.ts to configure what you want to whitelist
 * 2. Comment out items that are already whitelisted (for history)
 * 3. Run this script
 * 
 * The script will:
 * - Check current whitelist status of all items
 * - Only add items that are NOT already whitelisted
 * - Show detailed status before and after
 */

import { encodeFunctionData, getAddress } from 'viem';
import dotenv from "dotenv";
import { join } from "path";
import { whitelistConfig } from './whitelist/arbdata';

import {
  createClients,
  getRegistryAddress,
  checkWhitelistStatus,
  displayWhitelistStatus,
  filterByStatus,
  TARGET_REGISTRY_ABI,
} from './whitelist/utils';


// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

async function main() {
  console.log("🚀 Add to Whitelist");
  console.log("==================\n");

  // Initialize clients and get registry address
  const { publicClient, walletClient, account } = createClients();
  const registryAddress = getRegistryAddress();

  console.log("Configuration:");
  console.log("  Registry address:", registryAddress);
  console.log("  Account address:", account.address);
  console.log("  Items to process:", whitelistConfig.length);

  // Check current whitelist status
  console.log("\n🔍 Checking current whitelist status...");
  const statuses = await checkWhitelistStatus(
    publicClient,
    registryAddress,
    whitelistConfig
  );

  displayWhitelistStatus(statuses);

  // Filter out already whitelisted items
  const notWhitelisted = filterByStatus(statuses, false);
  
  if (notWhitelisted.length === 0) {
    console.log("\n✅ All items are already whitelisted!");
    console.log("   If you want to add new items, edit hardhat/scripts/whitelist/data.ts");
    return;
  }
  console.log("Not whitelisted items:", notWhitelisted.length);

  // Prepare arrays for batch operation (only items NOT whitelisted)
  // Ensure all addresses are properly checksummed (EIP-55)
  const targetsToAdd = notWhitelisted.map(s => getAddress(s.item.target));
  const selectorsToAdd = notWhitelisted.map(s => s.item.selector);

  console.log(`\n📋 Preparing to whitelist ${notWhitelisted.length} item(s):`);
  notWhitelisted.forEach((status, index) => {
    console.log(`  ${index + 1}. ${status.item.description}`);
    console.log(`     Target: ${status.item.target}`);
    console.log(`     Selector: ${status.item.selector}`);
  });

  // Confirmation prompt (in production, you might want more sophisticated confirmation)
  console.log("\n⚠️  WARNING: You are about to add these items to the whitelist.");
  console.log("   This operation is immediate (no timelock).");
  console.log("   Press Ctrl+C to cancel, or wait 5 seconds to continue...\n");
  
  await new Promise(resolve => setTimeout(resolve, 5000));

  try {
    // Execute batch add to whitelist
    console.log("🚀 Sending transaction to add items to whitelist...");
    
    const txHash = await walletClient.sendTransaction({
      to: registryAddress,
      data: encodeFunctionData({
        abi: TARGET_REGISTRY_ABI,
        functionName: 'addToWhitelist',
        args: [targetsToAdd, selectorsToAdd],
      }),
    });

    console.log("✅ Transaction sent!");
    console.log("  Transaction hash:", txHash);

    // Wait for confirmation
    console.log("\n⏳ Waiting for transaction confirmation...");
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: txHash,
    });

    console.log("✅ Transaction confirmed!");
    console.log("  Block number:", receipt.blockNumber.toString());
    console.log("  Gas used:", receipt.gasUsed.toString());

    // Verify whitelist status after transaction
    console.log("\n🔍 Verifying whitelist status after transaction...");
    const newStatuses = await checkWhitelistStatus(
      publicClient,
      registryAddress,
      notWhitelisted.map(s => s.item)
    );

    displayWhitelistStatus(newStatuses);

    // Check if all were successfully added
    const allAdded = newStatuses.every(s => s.isWhitelisted);
    if (allAdded) {
      console.log("\n✅✅ All items successfully added to whitelist!");
    } else {
      console.log("\n⚠️  Warning: Some items may not have been added. Check transaction logs.");
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
