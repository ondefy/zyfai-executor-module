/**
 * Remove Targets and Selectors from Whitelist (Arbitrum Chain)
 * 
 * This script removes target+selector combinations from the TargetRegistry whitelist on Arbitrum.
 * 
 * USAGE:
 * 1. Edit hardhat/scripts/whitelist/arbdata.ts to configure what you want to remove in removeWhitelistConfig
 * 2. The script will use removeWhitelistConfig - you can add/remove items as needed
 * 3. Run this script
 * 
 * The script will:
 * - Check current whitelist status of all items
 * - Only remove items that ARE currently whitelisted
 * - Show detailed status before and after
 * 
 * NOTE: Use removeWhitelistConfig in arbdata.ts for consistency. Add items you want to remove there.
 */

import { encodeFunctionData, getAddress } from 'viem';
import dotenv from "dotenv";
import { join } from "path";
import { removeWhitelistConfig } from './whitelist/arbdata';
import {
  createArbitrumClients,
  getArbitrumRegistryAddress,
  checkWhitelistStatus,
  displayWhitelistStatus,
  filterByStatus,
  TARGET_REGISTRY_ABI,
} from './whitelist/utils';

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

async function main() {
  console.log("🗑️  Remove from Whitelist (Arbitrum Chain)");
  console.log("========================================\n");

  // Initialize clients and get registry address
  const { publicClient, walletClient, account } = createArbitrumClients();
  const registryAddress = getArbitrumRegistryAddress();

  console.log("Configuration:");
  console.log("  Chain: Arbitrum (42161)");
  console.log("  Registry address:", registryAddress);
  console.log("  Account address:", account.address);
  console.log("  Items to process:", removeWhitelistConfig.length);

  // Check current whitelist status
  console.log("\n🔍 Checking current whitelist status...");
  const statuses = await checkWhitelistStatus(
    publicClient,
    registryAddress,
    removeWhitelistConfig
  );

  displayWhitelistStatus(statuses);

  // Filter to only whitelisted items (those we can remove)
  const currentlyWhitelisted = filterByStatus(statuses, true);
  
  if (currentlyWhitelisted.length === 0) {
    console.log("\n✅ No items are currently whitelisted from this configuration!");
    console.log("   If you want to remove items, make sure they are in removeWhitelistConfig in arbdata.ts");
    return;
  }

  // Prepare arrays for batch operation (only items that ARE whitelisted)
  // Ensure all addresses are properly checksummed (EIP-55)
  const targetsToRemove = currentlyWhitelisted.map(s => getAddress(s.item.target));
  const selectorsToRemove = currentlyWhitelisted.map(s => s.item.selector);

  console.log(`\n📋 Preparing to remove ${currentlyWhitelisted.length} item(s) from whitelist:`);
  currentlyWhitelisted.forEach((status, index) => {
    console.log(`  ${index + 1}. ${status.item.description}`);
    console.log(`     Target: ${status.item.target}`);
    console.log(`     Selector: ${status.item.selector}`);
  });

  // Confirmation prompt
  console.log("\n⚠️  WARNING: You are about to REMOVE these items from the whitelist.");
  console.log("   This operation is immediate and cannot be easily undone.");
  console.log("   Press Ctrl+C to cancel, or wait 5 seconds to continue...\n");
  
  await new Promise(resolve => setTimeout(resolve, 5000));

  try {
    // Execute batch remove from whitelist
    console.log("🚀 Sending transaction to remove items from whitelist...");
    
    const txHash = await walletClient.sendTransaction({
      to: registryAddress,
      data: encodeFunctionData({
        abi: TARGET_REGISTRY_ABI,
        functionName: 'removeFromWhitelist',
        args: [targetsToRemove, selectorsToRemove],
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
      currentlyWhitelisted.map(s => s.item)
    );

    displayWhitelistStatus(newStatuses);

    // Check if all were successfully removed
    const allRemoved = newStatuses.every(s => !s.isWhitelisted);
    if (allRemoved) {
      console.log("\n✅✅ All items successfully removed from whitelist!");
    } else {
      console.log("\n⚠️  Warning: Some items may still be whitelisted. Check transaction logs.");
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

