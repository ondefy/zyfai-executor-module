/**
 * Whitelist Configuration Data
 * 
 * This file contains all whitelist configurations (targets + selectors).
 * 
 * USAGE:
 * - Comment out items that are already whitelisted to maintain history
 * - Uncomment/add new items you want to whitelist
 * - Use the same format for both add and remove operations
 * 
 * TIPS:
 * - Keep commented items for reference/history
 * - Add clear descriptions for each entry
 * - Group related targets together
 */

import { Address } from 'viem';

/**
 * ERC20 Token Addresses (Base Chain)
 */
export const TOKENS = {
  USDC: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831' as Address,
} as const;

/**
 * AAVE Pool Addresses (Base Chain)
 */
export const AAVE_POOLS = {
  USDC: '0x794a61358D6845594F94dc1DB02A252b5b4814aD' as Address,
} as const;

/**
 * Fluid Pool Addresses (Base Chain)
 */
export const FLUID_POOLS = {
  USDC: '0x1A996cb54bb95462040408C06122D45D6Cdb6096' as Address,
} as const;

/**
 * Spark Pool Addresses (Base Chain)
 */
export const SPARK_POOLS = {
  USDC: '0x940098b108fB7D0a7E374f6eDED7760787464609' as Address,
} as const;

/**
 * Compound V3 Pool Addresses (Base Chain)
 */
export const COMPOUND_V3_POOLS = {
  USDC: '0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf' as Address,
} as const;
/**
 * Harvest Pool Addresses (Base Chain)
 */
export const HARVEST_POOLS = {
  'USDC - Autopilot': '0x407D3d942d0911a2fEA7E22417f81E27c02D6c6F' as Address,
} as const;

export const ARBITRUM_MORPHO_POOLS = {
  'Gauntlet USDC Prime': '0x7c574174DA4b2be3f705c6244B4BfA0815a8B3Ed',
  'Gauntlet USDC Core': '0x7e97fa6893871A2751B5fE961978DCCb2c201E65',
  'Steakhouse Prime USDC': '0x250CF7c82bAc7cB6cf899b6052979d4B5BA1f9ca',
  'MEV Capital USDC': '0xa60643c90A542A95026C0F1dbdB0615fF42019Cf',
  'Hyperithm USDC': '0x4B6F1C9E5d470b97181786b26da0d0945A7cf027',
  'Steakhouse High Yield USDC': '0x5c0C306Aaa9F877de636f4d5822cA9F2E81563BA',
};

/**
 * Legacy CONTRACTS export for backward compatibility
 * @deprecated Use specific pool exports (AAVE_POOLS, FLUID_POOLS, SPARK_POOLS, WASABI_POOLS, COMPOUND_V3_POOLS, MOONWELL_POOLS, HARVEST_POOLS, MORPHO_POOLS) instead
 */
export const CONTRACTS = {
  USDC: TOKENS.USDC,
  AAVE_POOL_USDC: AAVE_POOLS.USDC,
  FLUID_POOL_USDC: FLUID_POOLS.USDC,
  SPARK_POOL_USDC: SPARK_POOLS.USDC,
  COMPOUND_V3_POOL_USDC: COMPOUND_V3_POOLS.USDC,
} as const;

/**
 * Whitelist Item Interface
 */
export interface WhitelistItem {
  target: Address;
  selector: `0x${string}`;
  description: string;
}

/**
 * Function Selectors
 * Calculate using: toFunctionSelector(getAbiItem({ abi: [...], name: 'functionName' }))
 */
export const SELECTORS = {
  // ERC20 functions
  ERC20_APPROVE: '0x095ea7b3' as `0x${string}`, // approve(address,uint256)
  ERC20_TRANSFER: '0xa9059cbb' as `0x${string}`, // transfer(address,uint256)
  
  // AAVE Pool functions
  AAVE_SUPPLY: '0x617ba037' as `0x${string}`, // supply(address,uint256,address,uint16)
  AAVE_WITHDRAW: '0x69328dec' as `0x${string}`, // withdraw(address,uint256,address)
  
  // Compound V3 Pool functions (different from AAVE - uses 2 params instead of 3-4)
  COMPOUND_V3_SUPPLY: '0xf2b9fdb8' as `0x${string}`, // supply(address,uint256)
  COMPOUND_V3_WITHDRAW: '0xf3fef3a3' as `0x${string}`, // withdraw(address,uint256)
  
  // Fluid, Spark, Wasabi & Morpho Pool functions (ERC4626 standard - same ABI)
  ERC4626_DEPOSIT: '0x6e553f65' as `0x${string}`, // deposit(uint256,address)
  ERC4626_WITHDRAW: '0xb460af94' as `0x${string}`, // withdraw(uint256,address,address)
  
  // Harvest Autopilot uses redeem instead of withdraw
  REDEEM: '0xba087652' as `0x${string}`, // redeem(uint256,address,address)
  
  // Routing/Swap functions
  ROUTE_SINGLE: '0xb94c3609' as `0x${string}`, // routeSingle(...)
  
  // Morpho Adapter functions
  MORPHO_ADAPTER_ERC4626_DEPOSIT: '0x6ef5eeae' as `0x${string}`, // erc4626Deposit(address,uint256,uint256,address)
  MORPHO_ADAPTER_ERC4626_REDEEM: '0xa7f6e606' as `0x${string}`, // erc4626Redeem(address,uint256,uint256,address,address)
  
  // Morpho Bundler functions
  MORPHO_BUNDLER_MULTICALL: '0x374f435d' as `0x${string}`, // multicall((address,bytes,uint256,bool,bytes32)[])
  
  // Merkl functions
  MERKL_CLAIM: '0x71ee95c0' as `0x${string}`, // claim(address[],address[],uint256[],bytes32[][])
  
  // SiloV2 functions
  SILO_CLAIM_REWARDS: '0xef5cfb8c' as `0x${string}`, // claimRewards(address)
} as const;

/**
 * WHITELIST CONFIGURATION
 * 
 * Structure your whitelist items here.
 * Comment out items that are already whitelisted to maintain history.
 * 
 * Example:
 * 
 * // Already whitelisted (2024-01-15)
 * // { target: CONTRACTS.AAVE_POOL, selector: '0x69328dec', description: "AAVE Pool supply()" },
 * 
 * // New items to whitelist
 * { target: CONTRACTS.AAVE_POOL, selector: '0x69328dec', description: "AAVE Pool supply()" },
 */
export const whitelistConfig: WhitelistItem[] = [
  // ========================================
  // ERC20 TOKEN FUNCTIONS
  // ========================================
  {
    target: TOKENS.USDC,
    selector: SELECTORS.ERC20_APPROVE,
    description: "USDC approve()",
  },
  {
    target: TOKENS.USDC,
    selector: SELECTORS.ERC20_TRANSFER,
    description: "USDC transfer()",
  },
  
  // ========================================
  // AAVE POOL FUNCTIONS
  // ========================================
  {
    target: AAVE_POOLS.USDC,
    selector: SELECTORS.AAVE_SUPPLY,
    description: "AAVE Pool USDC - supply()",
  },
  {
    target: AAVE_POOLS.USDC,
    selector: SELECTORS.AAVE_WITHDRAW,
    description: "AAVE Pool USDC - withdraw()",
  },
  
  // ========================================
  // ROUTING/SWAP FUNCTIONS
  // ========================================
  {
    target: '0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf' as Address,
    selector: SELECTORS.ROUTE_SINGLE,
    description: "Router - routeSingle()",
  },
  
  // ========================================
  // MORPHO ADAPTER/BUNDLER FUNCTIONS (Arbitrum)
  // ========================================
  {
    target: '0x9954aFB60BB5A222714c478ac86990F221788B88' as Address,
    selector: SELECTORS.MORPHO_ADAPTER_ERC4626_DEPOSIT,
    description: "Morpho Adapter (Arbitrum) - erc4626Deposit()",
  },
  {
    target: '0x9954aFB60BB5A222714c478ac86990F221788B88' as Address,
    selector: SELECTORS.MORPHO_ADAPTER_ERC4626_REDEEM,
    description: "Morpho Adapter (Arbitrum) - erc4626Redeem()",
  },
  {
    target: '0x1fa4431bc113d308bee1d46b0e98cb805fb48c13' as Address,
    selector: SELECTORS.MORPHO_BUNDLER_MULTICALL,
    description: "Morpho Bundler3 (Arbitrum) - multicall()",
  },
  
  // ========================================
  // EULER EARN USDC (Arbitrum)
  // ========================================
  {
    target: '0xe4783824593a50Bfe9dc873204CEc171ebC62dE0' as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Euler Earn USDC (Arbitrum) - deposit()",
  },
  {
    target: '0xe4783824593a50Bfe9dc873204CEc171ebC62dE0' as Address,
    selector: SELECTORS.REDEEM,
    description: "Euler Earn USDC (Arbitrum) - redeem()",
  },
  
  // ========================================
  // MERKL DISTRIBUTOR (Arbitrum)
  // ========================================
  {
    target: '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae' as Address,
    selector: SELECTORS.MERKL_CLAIM,
    description: "Merkl Distributor (Arbitrum) - claim()",
  },
  
  // ========================================
  // SILOV2 REWARDS CLAIMER (Arbitrum)
  // ========================================
  {
    target: '0x43f8d8995C1b6b37Ca624C49819D671C8dcCe390' as Address,
    selector: SELECTORS.SILO_CLAIM_REWARDS,
    description: "SiloV2 RewardsClaimer (Arbitrum) - claimRewards()",
  },

  // ========================================
  // FLUID POOL FUNCTIONS
  // ========================================
  {
    target: FLUID_POOLS.USDC,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Fluid Pool USDC - deposit()",
  },
  // {
  //   target: FLUID_POOLS.USDC,
  //   selector: SELECTORS.ERC4626_WITHDRAW,
  //   description: "Fluid Pool USDC - withdraw()",
  // },
  {
    target: FLUID_POOLS.USDC,
    selector: SELECTORS.REDEEM,
    description: "Fluid Pool USDC - redeem()",
  },
  
  // ========================================
  // SPARK POOL FUNCTIONS
  // ========================================
  {
    target: SPARK_POOLS.USDC,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Spark Pool USDC - deposit()",
  },
  // {
  //   target: SPARK_POOLS.USDC,
  //   selector: SELECTORS.ERC4626_WITHDRAW,
  //   description: "Spark Pool USDC - withdraw()",
  // },
  {
    target: SPARK_POOLS.USDC,
    selector: SELECTORS.REDEEM,
    description: "Spark Pool USDC - redeem()",
  },
  
  // ========================================
  // COMPOUND V3 POOL FUNCTIONS
  // ========================================
  {
    target: COMPOUND_V3_POOLS.USDC,
    selector: SELECTORS.COMPOUND_V3_SUPPLY,
    description: "Compound V3 Pool USDC - supply()",
  },
  {
    target: COMPOUND_V3_POOLS.USDC,
    selector: SELECTORS.COMPOUND_V3_WITHDRAW,
    description: "Compound V3 Pool USDC - withdraw()",
  },
  
  
  // ========================================
  // HARVEST POOL FUNCTIONS
  // ========================================
  // USDC - Moonwell (uses standard ERC4626 deposit/withdraw)
  {
    target: HARVEST_POOLS['USDC - Autopilot'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Harvest USDC - Moonwell - deposit()",
  },
  // {
  //   target: HARVEST_POOLS['USDC - Autopilot'],
  //   selector: SELECTORS.ERC4626_WITHDRAW,
  //   description: "Harvest USDC - Moonwell - withdraw()",
  // },
  {
    target: HARVEST_POOLS['USDC - Autopilot'],
    selector: SELECTORS.REDEEM,
    description: "Harvest USDC - Moonwell - redeem()",
  },
  
  // // ========================================
  // // MORPHO POOL FUNCTIONS
  // // ========================================
  // Universal - USDC
  {
    target: ARBITRUM_MORPHO_POOLS['Gauntlet USDC Prime'] as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Gauntlet USDC Prime - deposit()",
  },
  {
    target: ARBITRUM_MORPHO_POOLS['Gauntlet USDC Prime'] as Address,
    selector: SELECTORS.REDEEM,
    description: "Morpho Gauntlet USDC Prime - redeem()",
  },
  
  {
    target: ARBITRUM_MORPHO_POOLS['Gauntlet USDC Core'] as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Gauntlet USDC Core - deposit()",
  },
  {
    target: ARBITRUM_MORPHO_POOLS['Gauntlet USDC Core'] as Address,
    selector: SELECTORS.REDEEM,
    description: "Morpho Gauntlet USDC Core - redeem()",
  },

  {
    target: ARBITRUM_MORPHO_POOLS['Steakhouse Prime USDC'] as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Steakhouse Prime USDC - deposit()",
  },
  {
    target: ARBITRUM_MORPHO_POOLS['Steakhouse Prime USDC'] as Address,
    selector: SELECTORS.REDEEM,
    description: "Morpho Steakhouse Prime USDC - redeem()",
  },
  
  {
    target: ARBITRUM_MORPHO_POOLS['MEV Capital USDC'] as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho MEV Capital USDC - deposit()",
  },
  {
    target: ARBITRUM_MORPHO_POOLS['MEV Capital USDC'] as Address,
    selector: SELECTORS.REDEEM,
    description: "Morpho MEV Capital USDC - redeem()",
  },

  {
    target: ARBITRUM_MORPHO_POOLS['Steakhouse High Yield USDC'] as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Steakhouse High Yield USDC - deposit()",
  },
  {
    target: ARBITRUM_MORPHO_POOLS['Steakhouse High Yield USDC'] as Address,
    selector: SELECTORS.REDEEM,
    description: "Morpho Steakhouse High Yield USDC - redeem()",
  },

  {
    target: ARBITRUM_MORPHO_POOLS['Hyperithm USDC'] as Address,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Hyperithm USDC - deposit()",
  },
  {
    target: ARBITRUM_MORPHO_POOLS['Hyperithm USDC'] as Address,
    selector: SELECTORS.REDEEM,
    description: "Morpho Hyperithm USDC - redeem()",
  },

  {
    target: '0xb98c948cfa24072e58935bc004a8a7b376ae746a' as Address,
    selector: SELECTORS.MORPHO_ADAPTER_ERC4626_REDEEM,
    description: "Morpho Adapter (Base) - erc4626Redeem()",
  },
];

/**
 * Helper function to filter out commented items
 * In practice, we'll just export the array and let users comment items directly
 */
export function getActiveWhitelistItems(): WhitelistItem[] {
  return whitelistConfig;
}

/**
 * Get targets and selectors arrays from config
 * Useful for batch operations
 */
export function getTargetsAndSelectors(): { targets: Address[]; selectors: `0x${string}`[] } {
  const config = getActiveWhitelistItems();
  return {
    targets: config.map(item => item.target),
    selectors: config.map(item => item.selector),
  };
}

