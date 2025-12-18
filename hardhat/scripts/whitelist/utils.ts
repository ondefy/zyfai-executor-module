/**
 * Whitelist Utility Functions
 * 
 * Common utilities for whitelist management scripts
 */

import { privateKeyToAccount } from 'viem/accounts';
import { arbitrum, base, sonic, plasma } from 'viem/chains';
import { 
  createPublicClient,
  createWalletClient,
  http, 
  Address,
  parseAbi,
  getAddress,
} from 'viem';

/**
 * TargetRegistry ABI - Only the functions we need
 */
export const TARGET_REGISTRY_ABI = parseAbi([
  // Batch whitelist operations
  "function addToWhitelist(address[] calldata targets, bytes4[] calldata selectors) external",
  "function removeFromWhitelist(address[] calldata targets, bytes4[] calldata selectors) external",
  // Public mapping getters (auto-generated from public mappings)
  "function whitelist(address target, bytes4 selector) external view returns (bool)",
  "function whitelistedTargets(address target) external view returns (bool)",
  // Events
  "event TargetSelectorAdded(address indexed target, bytes4 indexed selector)",
  "event TargetSelectorRemoved(address indexed target, bytes4 indexed selector)",
]);

/**
 * Clients type for whitelist operations
 */
export type WhitelistClients = {
  publicClient: any;
  walletClient: any;
  account: ReturnType<typeof privateKeyToAccount>;
};

/**
 * Create clients from environment variables
 */
export function createClients(): WhitelistClients {
  const privateKey = process.env.BASE_PRIVATE_KEY;
  const rpcUrl = process.env.BASE_RPC_URL;

  if (!privateKey) {
    throw new Error("Missing required environment variable: BASE_PRIVATE_KEY");
  }
  if (!rpcUrl) {
    throw new Error("Missing required environment variable: BASE_RPC_URL");
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);

  const publicClient = createPublicClient({
    chain: base,
    transport: http(rpcUrl),
  });

  const walletClient = createWalletClient({
    account,
    chain: base,
    transport: http(rpcUrl),
  });

  return { publicClient, walletClient, account };
}

/**
 * Get registry address from environment
 */
export function getRegistryAddress(): Address {
  const registryAddress = process.env.TARGET_REGISTRY_ADDRESS;
  if (!registryAddress) {
    throw new Error("Missing required environment variable: TARGET_REGISTRY_ADDRESS");
  }
  return registryAddress as Address;
}

/**
 * Check if items are already whitelisted
 */
export async function checkWhitelistStatus(
  publicClient: any,
  registryAddress: Address,
  items: Array<{ target: Address; selector: `0x${string}`; description: string }>
): Promise<Array<{ item: typeof items[0]; isWhitelisted: boolean }>> {
  const statuses = await Promise.all(
    items.map(async (item) => {
      // Ensure address is properly checksummed (EIP-55)
      const checksummedTarget = getAddress(item.target);
      // Use public mapping getter instead of removed isWhitelisted function
      const isWhitelisted = await publicClient.readContract({
        address: registryAddress,
        abi: TARGET_REGISTRY_ABI,
        functionName: 'whitelist',
        args: [checksummedTarget, item.selector],
      });
      return { item, isWhitelisted };
    })
  );
  return statuses;
}

/**
 * Display whitelist status
 */
export function displayWhitelistStatus(
  statuses: Array<{ item: { description: string }; isWhitelisted: boolean }>
): void {
  console.log("\n📊 Whitelist Status:");
  statuses.forEach((status, index) => {
    const icon = status.isWhitelisted ? "✅" : "❌";
    console.log(`  ${icon} ${index + 1}. ${status.item.description} - ${status.isWhitelisted ? "WHITELISTED" : "NOT WHITELISTED"}`);
  });
}

/**
 * Filter items by whitelist status
 */
export function filterByStatus<T extends { isWhitelisted: boolean }>(
  statuses: T[],
  filterWhitelisted: boolean
): T[] {
  return statuses.filter(status => status.isWhitelisted === filterWhitelisted);
}

/**
 * Create clients for Plasma chain from environment variables
 */
export function createPlasmaClients(): WhitelistClients {
  const privateKey = process.env.PLASMA_PRIVATE_KEY;
  const rpcUrl = process.env.PLASMA_RPC_URL;

  if (!privateKey) {
    throw new Error("Missing required environment variable: PLASMA_PRIVATE_KEY");
  }
  if (!rpcUrl) {
    throw new Error("Missing required environment variable: PLASMA_RPC_URL");
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);

  const publicClient = createPublicClient({
    chain: plasma,
    transport: http(rpcUrl),
  });

  const walletClient = createWalletClient({
    account,
    chain: plasma,
    transport: http(rpcUrl),
  });

  return { publicClient, walletClient, account };
}

/**
 * Create clients for Sonic chain from environment variables
 */
export function createSonicClients(): WhitelistClients {
  const privateKey = process.env.SONIC_PRIVATE_KEY;
  const rpcUrl = process.env.SONIC_RPC_URL;

  if (!privateKey) {
    throw new Error("Missing required environment variable: SONIC_PRIVATE_KEY");
  }
  if (!rpcUrl) {
    throw new Error("Missing required environment variable: SONIC_RPC_URL");
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);

  const publicClient = createPublicClient({
    chain: sonic,
    transport: http(rpcUrl),
  });

  const walletClient = createWalletClient({
    account,
    chain: sonic,
    transport: http(rpcUrl),
  });

  return { publicClient, walletClient, account };
}

/**
 * Get registry address from environment (Plasma)
 */
export function getPlasmaRegistryAddress(): Address {
  const registryAddress = process.env.PLASMA_TARGET_REGISTRY_ADDRESS;
  if (!registryAddress) {
    throw new Error("Missing required environment variable: PLASMA_TARGET_REGISTRY_ADDRESS");
  }
  return registryAddress as Address;
}

/**
 * Get registry address from environment (Sonic)
 */
export function getSonicRegistryAddress(): Address {
  const registryAddress = process.env.SONIC_TARGET_REGISTRY_ADDRESS;
  if (!registryAddress) {
    throw new Error("Missing required environment variable: SONIC_TARGET_REGISTRY_ADDRESS");
  }
  return registryAddress as Address;
}

