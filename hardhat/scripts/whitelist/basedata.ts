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
  USDC: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' as Address,
} as const;

/**
 * AAVE Pool Addresses (Base Chain)
 */
export const AAVE_POOLS = {
  USDC: '0xA238Dd80C259a72e81d7e4664a9801593F98d1c5' as Address,
} as const;

/**
 * Fluid Pool Addresses (Base Chain)
 */
export const FLUID_POOLS = {
  USDC: '0xf42f5795D9ac7e9D757DB633D693cD548Cfd9169' as Address,
} as const;

/**
 * Spark Pool Addresses (Base Chain)
 */
export const SPARK_POOLS = {
  USDC: '0x3128a0F7f0ea68E7B7c9B00AFa7E41045828e858' as Address,
} as const;

/**
 * Wasabi Pool Addresses (Base Chain)
 */
export const WASABI_POOLS = {
  USDC: '0x1C4a802FD6B591BB71dAA01D8335e43719048B24' as Address,
} as const;

/**
 * Compound V3 Pool Addresses (Base Chain)
 */
export const COMPOUND_V3_POOLS = {
  USDC: '0xb125E6687d4313864e53df431d5425969c15Eb2F' as Address,
} as const;

/**
 * Moonwell Pool Addresses (Base Chain)
 */
export const MOONWELL_POOLS = {
  USDC: '0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22' as Address,
} as const;

/**
 * Harvest Pool Addresses (Base Chain)
 */
export const HARVEST_POOLS = {
  'USDC - Moonwell': '0x90613e167D42CA420942082157B42AF6fc6a8087' as Address,
  'USDC - Autopilot': '0x0d877Dc7C8Fa3aD980DfDb18B48eC9F8768359C4' as Address,
  'USDC - 40 Acres': '0xC777031D50F632083Be7080e51E390709062263E' as Address,
} as const;

/**
 * Morpho Pool Addresses (Base Chain)
 */
export const MORPHO_POOLS = {
  'Universal - USDC': '0xB7890CEE6CF4792cdCC13489D36D9d42726ab863' as Address,
  'Seamless USDC Vault': '0x616a4E1db48e22028f6bbf20444Cd3b8e3273738' as Address,
  'Moonwell Flagship USDC': '0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca' as Address,
  'HighYield Clearstar USDC': '0xE74c499fA461AF1844fCa84204490877787cED56' as Address,
  'Clearstar Reactor OpenEden Boosted USDC': '0x1D3b1Cd0a0f242d598834b3F2d126dC6bd774657' as Address,
  'Gauntlet USDC Prime': '0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61' as Address,
  'Gauntlet USDC Core': '0xc0c5689e6f4D256E861F65465b691aeEcC0dEb12' as Address,
  'Gauntlet USDC Frontier': '0x236919F11ff9eA9550A4287696C2FC9e18E6e890' as Address,
  'ExtrafiXLend USDC': '0x23479229e52Ab6aaD312D0B03DF9F33B46753B5e' as Address,
  'Steakhouse USDC': '0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183' as Address,
} as const;



/**
 * Legacy CONTRACTS export for backward compatibility
 * @deprecated Use specific pool exports (AAVE_POOLS, FLUID_POOLS, SPARK_POOLS, WASABI_POOLS, COMPOUND_V3_POOLS, MOONWELL_POOLS, HARVEST_POOLS, MORPHO_POOLS) instead
 */
export const CONTRACTS = {
  USDC: TOKENS.USDC,
  AAVE_POOL_USDC: AAVE_POOLS.USDC,
  FLUID_POOL_USDC: FLUID_POOLS.USDC,
  SPARK_POOL_USDC: SPARK_POOLS.USDC,
  WASABI_POOL_USDC: WASABI_POOLS.USDC,
  COMPOUND_V3_POOL_USDC: COMPOUND_V3_POOLS.USDC,
  MOONWELL_POOL_USDC: MOONWELL_POOLS.USDC,
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
  
  // Moonwell Pool functions (uses mint/redeem with single uint256 param)
  MOONWELL_MINT: '0xa0712d68' as `0x${string}`, // mint(uint256)
  MOONWELL_REDEEM: '0xdb006a75' as `0x${string}`, // redeem(uint256)
  
  // Fluid, Spark, Wasabi & Morpho Pool functions (ERC4626 standard - same ABI)
  ERC4626_DEPOSIT: '0x6e553f65' as `0x${string}`, // deposit(uint256,address)
  ERC4626_WITHDRAW: '0xb460af94' as `0x${string}`, // withdraw(uint256,address,address)
  
  // Harvest Autopilot uses redeem instead of withdraw
  REDEEM: '0xba087652' as `0x${string}`, // redeem(uint256,address,address)
  
  // Routing/Swap functions
  ROUTE_MULTI: '0xf52e33f5' as `0x${string}`, // routeMulti(...)
  ROUTE_SINGLE: '0xb94c3609' as `0x${string}`, // routeSingle(...)
  
  // Morpho Adapter functions
  MORPHO_ADAPTER_ERC4626_DEPOSIT: '0x6ef5eeae' as `0x${string}`, // erc4626Deposit(address,uint256,uint256,address)
  MORPHO_ADAPTER_ERC4626_REDEEM: '0xa7f6e606' as `0x${string}`, // erc4626Redeem(address,uint256,uint256,address,address)
  
  // Morpho Bundler functions
  MORPHO_BUNDLER_MULTICALL: '0x374f435d' as `0x${string}`, // multicall((address,bytes,uint256,bool,bytes32)[])
  
  // Merkl functions
  MERKL_CLAIM: '0x71ee95c0' as `0x${string}`, // claim(address[],address[],uint256[],bytes32[][])
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
  // MORPHO ADAPTER/BUNDLER FUNCTIONS (Base)
  // ========================================
  {
    target: '0xb98c948cfa24072e58935bc004a8a7b376ae746a' as Address,
    selector: SELECTORS.MORPHO_ADAPTER_ERC4626_DEPOSIT,
    description: "Morpho Adapter (Base) - erc4626Deposit()",
  },
  {
    target: '0xb98c948cfa24072e58935bc004a8a7b376ae746a' as Address,
    selector: SELECTORS.MORPHO_ADAPTER_ERC4626_REDEEM,
    description: "Morpho Adapter (Base) - erc4626Redeem()",
  },
  {
    target: '0x6BFd8137e702540E7A42B74178A4a49Ba43920C4' as Address,
    selector: SELECTORS.MORPHO_BUNDLER_MULTICALL,
    description: "Morpho Bundler3 (Base) - multicall()",
  },
  
  // ========================================
  // MERKL DISTRIBUTOR (Base)
  // ========================================
  {
    target: '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae' as Address,
    selector: SELECTORS.MERKL_CLAIM,
    description: "Merkl Distributor (Base) - claim()",
  },

  // ========================================
  // FLUID POOL FUNCTIONS
  // ========================================
  {
    target: FLUID_POOLS.USDC,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Fluid Pool USDC - deposit()",
  },
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
  {
    target: SPARK_POOLS.USDC,
    selector: SELECTORS.REDEEM,
    description: "Spark Pool USDC - redeem()",
  },
  
  // ========================================
  // WASABI POOL FUNCTIONS
  // ========================================
  {
    target: WASABI_POOLS.USDC,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Wasabi Pool USDC - deposit()",
  },
  {
    target: WASABI_POOLS.USDC,
    selector: SELECTORS.REDEEM,
    description: "Wasabi Pool USDC - redeem()",
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
  // MORPHO POOL FUNCTIONS (Base)
  // Only approve is needed for Morpho vaults per the provided list
  // ========================================
  {
    target: MORPHO_POOLS['Universal - USDC'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Universal - USDC - approve()",
  },
  {
    target: MORPHO_POOLS['Seamless USDC Vault'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Seamless USDC Vault - approve()",
  },
  {
    target: MORPHO_POOLS['Moonwell Flagship USDC'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Moonwell Flagship USDC - approve()",
  },
  {
    target: MORPHO_POOLS['HighYield Clearstar USDC'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho HighYield Clearstar USDC - approve()",
  },
  {
    target: MORPHO_POOLS['Clearstar Reactor OpenEden Boosted USDC'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Clearstar Reactor OpenEden Boosted USDC - approve()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Prime'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Gauntlet USDC Prime - approve()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Core'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Gauntlet USDC Core - approve()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Frontier'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Gauntlet USDC Frontier - approve()",
  },
  {
    target: MORPHO_POOLS['ExtrafiXLend USDC'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho ExtrafiXLend USDC - approve()",
  },
  {
    target: MORPHO_POOLS['Steakhouse USDC'],
    selector: SELECTORS.ERC20_APPROVE,
    description: "Morpho Steakhouse USDC - approve()",
  },
];

/**
 * REMOVE WHITELIST CONFIGURATION
 * 
 * Items to be removed from the whitelist.
 * These are items that were previously whitelisted but are no longer needed
 * based on the updated requirements.
 */
export const removeWhitelistConfig: WhitelistItem[] = [
  // ========================================
  // ROUTING/SWAP FUNCTIONS (To Remove)
  // ========================================
  {
    target: '0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf' as Address,
    selector: SELECTORS.ROUTE_MULTI,
    description: "Router - routeMulti()",
  },

  {
    target: FLUID_POOLS.USDC,
    selector: SELECTORS.ERC4626_WITHDRAW,
    description: "Fluid Pool USDC - withdraw()",
  },
  
  // ========================================
  // MOONWELL POOL FUNCTIONS (To Remove)
  // ========================================
  {
    target: MOONWELL_POOLS.USDC,
    selector: SELECTORS.MOONWELL_MINT,
    description: "Moonwell Pool USDC - mint()",
  },
  {
    target: MOONWELL_POOLS.USDC,
    selector: SELECTORS.MOONWELL_REDEEM,
    description: "Moonwell Pool USDC - redeem()",
  },
  
  // ========================================
  // MORPHO POOL DEPOSIT/REDEEM (To Remove)
  // Only approve should remain, deposit/redeem should be removed
  // ========================================
  {
    target: MORPHO_POOLS['Universal - USDC'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Universal - USDC - deposit()",
  },
  {
    target: MORPHO_POOLS['Universal - USDC'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Universal - USDC - redeem()",
  },
  {
    target: MORPHO_POOLS['Seamless USDC Vault'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Seamless USDC Vault - deposit()",
  },
  {
    target: MORPHO_POOLS['Seamless USDC Vault'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Seamless USDC Vault - redeem()",
  },
  {
    target: MORPHO_POOLS['Moonwell Flagship USDC'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Moonwell Flagship USDC - deposit()",
  },
  {
    target: MORPHO_POOLS['Moonwell Flagship USDC'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Moonwell Flagship USDC - redeem()",
  },
  {
    target: MORPHO_POOLS['HighYield Clearstar USDC'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho HighYield Clearstar USDC - deposit()",
  },
  {
    target: MORPHO_POOLS['HighYield Clearstar USDC'],
    selector: SELECTORS.REDEEM,
    description: "Morpho HighYield Clearstar USDC - redeem()",
  },
  {
    target: MORPHO_POOLS['Clearstar Reactor OpenEden Boosted USDC'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Clearstar Reactor OpenEden Boosted USDC - deposit()",
  },
  {
    target: MORPHO_POOLS['Clearstar Reactor OpenEden Boosted USDC'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Clearstar Reactor OpenEden Boosted USDC - redeem()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Prime'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Gauntlet USDC Prime - deposit()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Prime'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Gauntlet USDC Prime - redeem()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Core'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Gauntlet USDC Core - deposit()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Core'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Gauntlet USDC Core - redeem()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Frontier'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Gauntlet USDC Frontier - deposit()",
  },
  {
    target: MORPHO_POOLS['Gauntlet USDC Frontier'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Gauntlet USDC Frontier - redeem()",
  },
  {
    target: MORPHO_POOLS['ExtrafiXLend USDC'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho ExtrafiXLend USDC - deposit()",
  },
  {
    target: MORPHO_POOLS['ExtrafiXLend USDC'],
    selector: SELECTORS.REDEEM,
    description: "Morpho ExtrafiXLend USDC - redeem()",
  },
  {
    target: MORPHO_POOLS['Steakhouse USDC'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Morpho Steakhouse USDC - deposit()",
  },
  {
    target: MORPHO_POOLS['Steakhouse USDC'],
    selector: SELECTORS.REDEEM,
    description: "Morpho Steakhouse USDC - redeem()",
  },
  
  // ========================================
  // HARVEST POOL FUNCTIONS (To Remove)
  // Not in the provided list - should be removed
  // ========================================
  {
    target: HARVEST_POOLS['USDC - Moonwell'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Harvest USDC - Moonwell - deposit()",
  },
  {
    target: HARVEST_POOLS['USDC - Moonwell'],
    selector: SELECTORS.REDEEM,
    description: "Harvest USDC - Moonwell - redeem()",
  },
  {
    target: HARVEST_POOLS['USDC - 40 Acres'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Harvest USDC - 40 Acres - deposit()",
  },
  {
    target: HARVEST_POOLS['USDC - 40 Acres'],
    selector: SELECTORS.REDEEM,
    description: "Harvest USDC - 40 Acres - redeem()",
  },
  {
    target: HARVEST_POOLS['USDC - Autopilot'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Harvest USDC - Autopilot - deposit()",
  },
  {
    target: HARVEST_POOLS['USDC - Autopilot'],
    selector: SELECTORS.REDEEM,
    description: "Harvest USDC - Autopilot - redeem()",
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

