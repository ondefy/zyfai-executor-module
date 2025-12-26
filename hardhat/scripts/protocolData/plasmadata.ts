/**
 * Whitelist Configuration Data for Plasma Chain (Chain ID 9745)
 * 
 * This file contains all whitelist configurations (targets + selectors) for Plasma.
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
 * ERC20 Token Addresses (Plasma Chain)
 */
export const TOKENS = {
  USDT0: '0xb8ce59fc3717ada4c02eadf9682a9e934f625ebb' as Address, // Update with actual USDT0 address if needed
  WXPL: '0x6100E367285b01F48D07953803A2d8dCA5D19873' as Address,
} as const;

/**
 * AAVE Pool Addresses (Plasma Chain)
 */
export const AAVE_POOLS = {
  USDT0: '0x925a2A7214Ed92428B5b1B090F80b25700095e12' as Address,
} as const;

/**
 * Euler Pool Addresses (Plasma Chain)
 */
export const EULER_POOLS = {
  'Re7 USDT0 Core': '0xa5EeD1615cd883dD6883ca3a385F525e3bEB4E79' as Address,
  'K3 Capital USDT0 Vault': '0xe818ad0D20D504C55601b9d5e0E137314414dec4' as Address,
  'Hyperithm Euler USDT': '0x66bE42a0BdA425A8C3b3c2cF4F4Cb9EDfcAEd21d' as Address,
} as const;

/**
 * Fluid Pool Addresses (Plasma Chain)
 */
export const FLUID_POOLS = {
  USDT0: '0x1DD4b13fcAE900C60a350589BE8052959D2Ed27B' as Address,
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
  
  // ERC4626 functions
  ERC4626_DEPOSIT: '0x6e553f65' as `0x${string}`, // deposit(uint256,address)
  REDEEM: '0xba087652' as `0x${string}`, // redeem(uint256,address,address)
  
  // Merkl functions
  MERKL_CLAIM: '0x71ee95c0' as `0x${string}`, // claim(address[],address[],uint256[],bytes32[][])
} as const;

/**
 * WHITELIST CONFIGURATION
 * 
 * Structure your whitelist items here.
 * Comment out items that are already whitelisted to maintain history.
 */
export const whitelistConfig: WhitelistItem[] = [
  // ========================================
  // ERC20 TOKEN FUNCTIONS
  // ========================================
  {
    target: TOKENS.WXPL,
    selector: SELECTORS.ERC20_APPROVE,
    description: "WXPL approve()",
  },
  {
    target: TOKENS.USDT0,
    selector: SELECTORS.ERC20_APPROVE,
    description: "USDT0 approve()",
  },
  {
    target: TOKENS.USDT0,
    selector: SELECTORS.ERC20_TRANSFER,
    description: "USDT0 transfer()",
  },
  
  // ========================================
  // AAVE POOL FUNCTIONS
  // ========================================
  {
    target: AAVE_POOLS.USDT0,
    selector: SELECTORS.AAVE_SUPPLY,
    description: "AAVE Pool USDT0 - supply()",
  },
  {
    target: AAVE_POOLS.USDT0,
    selector: SELECTORS.AAVE_WITHDRAW,
    description: "AAVE Pool USDT0 - withdraw()",
  },
  
  // ========================================
  // EULER POOL FUNCTIONS
  // ========================================
  {
    target: EULER_POOLS['Re7 USDT0 Core'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Euler Re7 USDT0 Core - deposit()",
  },
  {
    target: EULER_POOLS['Re7 USDT0 Core'],
    selector: SELECTORS.REDEEM,
    description: "Euler Re7 USDT0 Core - redeem()",
  },
  {
    target: EULER_POOLS['K3 Capital USDT0 Vault'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Euler K3 Capital USDT0 Vault - deposit()",
  },
  {
    target: EULER_POOLS['K3 Capital USDT0 Vault'],
    selector: SELECTORS.REDEEM,
    description: "Euler K3 Capital USDT0 Vault - redeem()",
  },
  {
    target: EULER_POOLS['Hyperithm Euler USDT'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Euler Hyperithm Euler USDT - deposit()",
  },
  {
    target: EULER_POOLS['Hyperithm Euler USDT'],
    selector: SELECTORS.REDEEM,
    description: "Euler Hyperithm Euler USDT - redeem()",
  },
  
  // ========================================
  // FLUID POOL FUNCTIONS
  // ========================================
  {
    target: FLUID_POOLS.USDT0,
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Fluid Pool USDT0 - deposit()",
  },
  {
    target: FLUID_POOLS.USDT0,
    selector: SELECTORS.REDEEM,
    description: "Fluid Pool USDT0 - redeem()",
  },
  
  // ========================================
  // MERKL DISTRIBUTOR (Plasma)
  // ========================================
  {
    target: '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae' as Address,
    selector: SELECTORS.MERKL_CLAIM,
    description: "Merkl Distributor (Plasma) - claim()",
  },
];

/**
 * Helper function to filter out commented items
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

