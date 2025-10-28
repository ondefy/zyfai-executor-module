import { RhinestoneSDK } from '@rhinestone/sdk';
import { privateKeyToAccount, generatePrivateKey } from 'viem/accounts';
import { base } from 'viem/chains';
import { createPublicClient, http } from 'viem';
import dotenv from "dotenv";
import { join } from "path";
import { readFileSync, writeFileSync } from "fs";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

/**
 * Create and configure session keys using Rhinestone SDK
 */
async function main() {
  console.log("🔑 Creating session keys with Rhinestone SDK...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const safeAddress = process.env.SAFE_ACCOUNT_ADDRESS;
  const moduleAddress = process.env.GUARDED_EXEC_MODULE_ADDRESS;
  
  if (!privateKey || !safeAddress || !moduleAddress) {
    throw new Error("Missing required environment variables. Please run previous scripts first");
  }
  
  console.log("Safe address:", safeAddress);
  console.log("Module address:", moduleAddress);
  
  // Create account from private key
  const account = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("Account address:", account.address);
  
  // Create Rhinestone SDK instance
  const rhinestone = new RhinestoneSDK();
  
  // Get the Safe account
  const rhinestoneAccount = await rhinestone.getAccount({
    address: safeAddress as `0x${string}`,
    type: 'safe',
  });
  
  console.log("\n🔑 Generating session key...");
  
  // Generate a new session key
  const sessionKeyPrivateKey = generatePrivateKey();
  const sessionKeyAccount = privateKeyToAccount(sessionKeyPrivateKey);
  
  console.log("Session key address:", sessionKeyAccount.address);
  console.log("Session key private key:", sessionKeyPrivateKey);
  
  // Create session configuration
  const sessionConfig = {
    chainId: base.id,
    validUntil: Math.floor(Date.now() / 1000) + (24 * 60 * 60), // 24 hours from now
    permissions: [
      {
        target: moduleAddress as `0x${string}`,
        selector: '0x', // Allow all functions on the module
        valueLimit: 0n, // No value limit
        gasLimit: 1000000n, // 1M gas limit
      }
    ],
  };
  
  console.log("\n📋 Session configuration:");
  console.log("Chain ID:", sessionConfig.chainId);
  console.log("Valid until:", new Date(sessionConfig.validUntil * 1000).toISOString());
  console.log("Target:", sessionConfig.permissions[0].target);
  console.log("Gas limit:", sessionConfig.permissions[0].gasLimit.toString());
  
  console.log("\n🔐 Creating session...");
  
  // Create the session
  const session = await rhinestoneAccount.createSession({
    sessionKey: sessionKeyAccount,
    ...sessionConfig,
  });
  
  console.log("✅ Session created successfully");
  console.log("Session ID:", session.id);
  
  // Save session key to environment file
  const envPath = join(__dirname, "..", "env.base");
  let envContent = readFileSync(envPath, "utf8");
  
  // Update session key configuration
  envContent = envContent.replace(
    /SESSION_KEY_PRIVATE_KEY=.*/,
    `SESSION_KEY_PRIVATE_KEY=${sessionKeyPrivateKey}`
  );
  
  envContent = envContent.replace(
    /SESSION_KEY_VALID_UNTIL=.*/,
    `SESSION_KEY_VALID_UNTIL=${sessionConfig.validUntil}`
  );
  
  // Write back to file
  writeFileSync(envPath, envContent);
  
  console.log("\n💾 Session key saved to env.base");
  
  console.log("\n📝 Next steps:");
  console.log("1. Run: pnpm run setup-whitelist");
  console.log("2. Run: pnpm run test-integration");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error creating session key:", error);
    process.exit(1);
  });