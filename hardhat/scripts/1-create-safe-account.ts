import { 
  getOwnableValidator, 
  getAccount, 
  RHINESTONE_ATTESTER_ADDRESS
} from '@rhinestone/module-sdk';
import { toSafeSmartAccount } from 'permissionless/accounts';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { createPublicClient, createWalletClient, http, parseEther, fromHex, toHex } from 'viem';
import { entryPoint07Address } from 'viem/account-abstraction';
import dotenv from "dotenv";
import { join } from "path";
import { readFileSync, writeFileSync } from "fs";

// Load environment variables
dotenv.config({ path: join(__dirname, "..", ".env") });

const SAFE_7579_ADDRESS = '0x7579EE8307284F293B1927136486880611F20002';

/**
 * Create a Safe smart account using Rhinestone Module SDK
 */
async function main() {
  console.log("🏗️ Creating Safe smart account with Rhinestone Module SDK...");
  
  // Check environment variables
  const privateKey = process.env.BASE_PRIVATE_KEY;
  console.log("Private key:", privateKey);
  if (!privateKey) {
    throw new Error("BASE_PRIVATE_KEY not found in environment variables");
  }
  
  console.log("\n📋 Environment Check:");
  console.log("Private key found:", privateKey ? "✅" : "❌");
  
  // Create account from private key
  const account = privateKeyToAccount(privateKey as `0x${string}`);
  console.log("Account address:", account.address);
  
  console.log("\n🔧 Creating Safe account with Rhinestone Module SDK...");
  
  console.log("Base RPC URL:", process.env.BASE_RPC_URL);
  // Create public client with proper RPC URL
  const rpcUrl = process.env.BASE_RPC_URL;
  console.log("Using RPC URL:", rpcUrl);
  
  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl),
  });
  
  // Create ownable validator
  const ownableValidator = getOwnableValidator({
    owners: [account.address],
    threshold: 1,
  });
  
  // Create Safe account using toSafeSmartAccount
  const safeAccount = await toSafeSmartAccount({
    client: publicClient,
    owners: [account],
    version: '1.4.1',
    entryPoint: {
      address: entryPoint07Address,
      version: '0.7',
    },
    safe4337ModuleAddress: SAFE_7579_ADDRESS,
    erc7579LaunchpadAddress: '0x7579011aB74c46090561ea277Ba79D510c6C00ff',
    attesters: [
      RHINESTONE_ATTESTER_ADDRESS, // Rhinestone Attester
    ],
    attestersThreshold: 1,
    validators: [
      {
        address: ownableValidator.address,
        context: ownableValidator.initData,
      },
    ],
    saltNonce: fromHex(toHex(process.env.ACCOUNT_SALT || '0x1'), 'bigint'),
  });
  
  const safeAddress = await safeAccount.getAddress();
  console.log("Safe account address:", safeAddress);
  
  // Check if account is already deployed
  const code = await publicClient.getCode({ address: safeAddress });
  console.log("Safe account code length:", code?.length || 0);
  
  if (code && code !== '0x') {
    console.log("✅ Safe account is already deployed");
  } else {
    console.log("📦 Deploying Safe account...");
    
    // Create smart account client for deployment
    const getPimlicoUrl = (networkId: number) => {
      const apiKey = 'pim_Pj8F4e4yjMiBej7UmJjgcC';
      const baseUrl = 'https://api.pimlico.io/v2/';
      return `${baseUrl}${networkId}/rpc?apikey=${apiKey}`;
    };
    
    const pimlicoUrl = getPimlicoUrl(base.id);
    console.log("Pimlico URL:", pimlicoUrl);
    
    const { createPimlicoClient } = await import('permissionless/clients/pimlico');
    const { createSmartAccountClient } = await import('permissionless');
    const { erc7579Actions } = await import('permissionless/actions/erc7579');
    
    const pimlicoClient = createPimlicoClient({
      transport: http(pimlicoUrl),
      entryPoint: {
        address: entryPoint07Address,
        version: '0.7',
      },
    });
    
    const smartAccountClient = createSmartAccountClient({
      account: safeAccount,
      chain: base,
      bundlerTransport: http(pimlicoUrl),
      paymaster: pimlicoClient,
      userOperation: {
        estimateFeesPerGas: async () => {
          return (await pimlicoClient.getUserOperationGasPrice()).fast;
        },
      },
    }).extend(erc7579Actions());
    console.log("Smart account client:", safeAddress);
    

    // Deploy the account by sending a simple transaction
    console.log("Sending deployment transaction...", safeAddress);
    const deploymentTx = await smartAccountClient.sendTransaction({
      to: safeAddress,
      value: 0n,
      data: '0x',
    });
    
    console.log("Deployment transaction:", deploymentTx);
    
    // Wait for deployment
    const deploymentResult = await smartAccountClient.waitForUserOperationReceipt({
      hash: deploymentTx,
    });
    
    console.log("✅ Safe account deployed successfully:", deploymentResult);
  }
  
  // // Fund the account with some ETH for gas
  // console.log("\n💰 Funding account...");
  
  // const walletClient = createWalletClient({
  //   account,
  //   chain: base,
  //   transport: http(rpcUrl),
  // });
  
  // // Check if account needs funding
  // const balance = await publicClient.getBalance({ address: safeAddress });
  // console.log("Safe account balance:", balance.toString(), "wei");

  // const balance2 = await publicClient.getBalance({ address: account.address });
  // console.log("Owner account balance:", balance2.toString(), "wei");
  
  // if (balance < parseEther("0.001")) {
  //   // console.log("Funding Safe account with 0.001 ETH...");
  //   // const txHash = await walletClient.sendTransaction({
  //   //   to: safeAddress,
  //   //   value: parseEther("0.001"),
  //   // });
    
  //   // await publicClient.waitForTransactionReceipt({ hash: txHash });
  //   // console.log("Funding transaction:", txHash);
  // } else {
  //   console.log("Safe account already has sufficient balance");
  // }
  
  // // // Save to environment file
  // const envPath = join(__dirname, "..", "env.base");
  // let envContent = readFileSync(envPath, "utf8");
  // console.log("Env content:", envContent);
  
  // // Update SAFE_ACCOUNT_ADDRESS
  // envContent = envContent.replace(
  //   /SAFE_ACCOUNT_ADDRESS=.*/,
  //   `SAFE_ACCOUNT_ADDRESS=${safeAddress}`
  // );
  // console.log("Env content-2:", envContent);
  
  // // Write back to file
  // writeFileSync(envPath, envContent);
  
  // console.log("\n✅ Safe account created and saved to env.base");
  // console.log("Safe Address:", safeAddress);
  
  // console.log("\n📝 Next steps:");
  // console.log("1. Run: pnpm run install-module");
  // console.log("2. Run: pnpm run setup-whitelist");
  // console.log("3. Run: pnpm run create-session-key");
  // console.log("4. Run: pnpm run test-integration");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error creating Safe account:", error);
    process.exit(1);
  });