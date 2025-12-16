/**
 * Add ERC20 Token Recipient to TargetRegistry
 * 
 * This script adds authorized recipient(s) for a specific ERC20 token to the TargetRegistry.
 * 
 * USAGE:
 * 1. Edit the TOKEN and RECIPIENTS constants below to configure what you want to authorize
 * 2. Run this script
 * 
 * The script will:
 * - Check current authorization status of all recipients
 * - Only add recipients that are NOT already authorized
 * - Show detailed status before and after
 */

import { encodeFunctionData, getAddress, parseAbi } from 'viem';
import dotenv from "dotenv";
import { join } from "path";
import {
  createClients,
  getRegistryAddress,
} from './whitelist/utils';

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * TargetRegistry ABI - ERC20 recipient functions
 */
const TARGET_REGISTRY_ABI = parseAbi([
  "function addAllowedERC20TokenRecipient(address token, address[] calldata recipients) external",
  "function allowedERC20TokenRecipients(address token, address recipient) external view returns (bool)",
  "event ERC20TokenRecipientAuthorized(address indexed token, address indexed recipient, bool authorized)",
]);

/**
 * Configuration
 * Edit these values to configure what you want to authorize
 */
const TOKEN = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as const; // USDC on Base
// const TOKEN = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831' as const; // USDC on Arbitrum
const BASE_RECIPIENTS = [
  // '0x62be78705295ca9ffdac410b4a9b6101983a7c3b' as const,
  // '0x23479229e52Ab6aaD312D0B03DF9F33B46753B5e' as const,
  '0xb98c948CFA24072e58935BC004a8A7b376AE746A' as const,
];

async function main() {
  console.log("🚀 Add ERC20 Token Recipient");
  console.log("=============================\n");

  // Initialize clients and get registry address
  const { publicClient, walletClient, account } = createClients();
  const registryAddress = getRegistryAddress();

  console.log("Configuration:");
  console.log("  Registry address:", registryAddress);
  console.log("  Account address:", account.address);
  console.log("  Token address:", TOKEN);
  console.log("  Recipients to process:", BASE_RECIPIENTS.length);

  // Check current authorization status
  console.log("\n🔍 Checking current authorization status...");
  const statuses = await Promise.all(
    BASE_RECIPIENTS.map(async (recipient) => {
      const checksummedRecipient = getAddress(recipient);
      const isAuthorized = await publicClient.readContract({
        address: registryAddress,
        abi: TARGET_REGISTRY_ABI,
        functionName: 'allowedERC20TokenRecipients',
        args: [TOKEN, checksummedRecipient],
      });
      return { recipient: checksummedRecipient, isAuthorized };
    })
  );

  console.log("\n📊 Authorization Status:");
  statuses.forEach((status, index) => {
    const icon = status.isAuthorized ? "✅" : "❌";
    console.log(`  ${icon} ${index + 1}. ${status.recipient} - ${status.isAuthorized ? "AUTHORIZED" : "NOT AUTHORIZED"}`);
  });

  // Filter out already authorized recipients
  const notAuthorized = statuses.filter(s => !s.isAuthorized);
  
  if (notAuthorized.length === 0) {
    console.log("\n✅ All recipients are already authorized!");
    console.log("   If you want to add new recipients, edit the RECIPIENTS array in this script");
    return;
  }
  console.log("\nNot authorized recipients:", notAuthorized.length);

  // Prepare array for batch operation (only recipients NOT authorized)
  // Ensure all addresses are properly checksummed (EIP-55)
  const recipientsToAdd = notAuthorized.map(s => getAddress(s.recipient));

  console.log(`\n📋 Preparing to authorize ${notAuthorized.length} recipient(s):`);
  notAuthorized.forEach((status, index) => {
    console.log(`  ${index + 1}. ${status.recipient}`);
  });

  // Confirmation prompt
  console.log("\n⚠️  WARNING: You are about to authorize these recipients for ERC20 transfers.");
  console.log("   Token:", TOKEN);
  console.log("   This operation is immediate (no timelock).");
  console.log("   Press Ctrl+C to cancel, or wait 5 seconds to continue...\n");
  
  await new Promise(resolve => setTimeout(resolve, 5000));

  try {
    // Execute batch add authorized recipients
    console.log("🚀 Sending transaction to authorize recipients...");
    
    const txHash = await walletClient.sendTransaction({
      to: registryAddress,
      data: encodeFunctionData({
        abi: TARGET_REGISTRY_ABI,
        functionName: 'addAllowedERC20TokenRecipient',
        args: [TOKEN, recipientsToAdd],
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

    // Verify authorization status after transaction
    console.log("\n🔍 Verifying authorization status after transaction...");
    const newStatuses = await Promise.all(
      notAuthorized.map(async (status) => {
        const isAuthorized = await publicClient.readContract({
          address: registryAddress,
          abi: TARGET_REGISTRY_ABI,
          functionName: 'allowedERC20TokenRecipients',
          args: [TOKEN, status.recipient],
        });
        return { recipient: status.recipient, isAuthorized };
      })
    );

    console.log("\n📊 Authorization Status After Transaction:");
    newStatuses.forEach((status, index) => {
      const icon = status.isAuthorized ? "✅" : "❌";
      console.log(`  ${icon} ${index + 1}. ${status.recipient} - ${status.isAuthorized ? "AUTHORIZED" : "NOT AUTHORIZED"}`);
    });

    // Check if all were successfully authorized
    const allAuthorized = newStatuses.every(s => s.isAuthorized);
    if (allAuthorized) {
      console.log("\n✅✅ All recipients successfully authorized!");
    } else {
      console.log("\n⚠️  Warning: Some recipients may not have been authorized. Check transaction logs.");
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

