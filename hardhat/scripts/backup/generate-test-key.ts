import { generatePrivateKey } from 'viem/accounts';
import { writeFileSync, readFileSync } from 'fs';
import { join } from 'path';

/**
 * Generate a test private key for development
 */
async function main() {
  console.log("🔑 Generating test private key...");
  
  // Generate a new private key
  const privateKey = generatePrivateKey();
  console.log("Generated private key:", privateKey);
  
  // Read the .env file
  const envPath = join(__dirname, "..", ".env");
  let envContent = readFileSync(envPath, "utf8");
  
  // Update the private key
  envContent = envContent.replace(
    /BASE_PRIVATE_KEY=.*/,
    `BASE_PRIVATE_KEY=${privateKey}`
  );
  
  // Update the session key as well
  const sessionKey = generatePrivateKey();
  envContent = envContent.replace(
    /SESSION_KEY_PRIVATE_KEY=.*/,
    `SESSION_KEY_PRIVATE_KEY=${sessionKey}`
  );
  
  // Write back to file
  writeFileSync(envPath, envContent);
  
  console.log("✅ Test keys generated and saved to .env");
  console.log("Base Private Key:", privateKey);
  console.log("Session Key:", sessionKey);
  
  console.log("\n📝 Next steps:");
  console.log("1. Fund the account with some ETH from a faucet");
  console.log("2. Run: pnpm run create-safe-account");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error generating keys:", error);
    process.exit(1);
  });
