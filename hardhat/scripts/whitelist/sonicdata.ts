/**
 * Whitelist Configuration Data for Sonic Chain (Chain ID 146)
 * 
 * This file contains all whitelist configurations (targets + selectors) for Sonic.
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
 * ERC20 Token Addresses (Sonic Chain)
 */
export const TOKENS = {
  USDCe: '0x29219dd400f2Bf60E5a23d13Be72B486D4038894' as Address, // Update with actual USDC.e address if needed
} as const;

/**
 * AAVE Pool Addresses (Sonic Chain)
 */
export const AAVE_POOLS = {
  USDCe: '0x5362dbb1e601abf3a4c14c22ffeda64042e5eaa3' as Address,
} as const;

/**
 * Euler Pool Addresses (Sonic Chain)
 */
export const EULER_POOLS = {
  'MEV Capital Sonic Cluster USDC.e': '0x196F3C7443E940911EE2Bb88e019Fd71400349D9' as Address,
  'Re7 Labs Cluster USDC.e': '0x3D9e5462A940684073EED7e4a13d19AE0Dcd13bc' as Address,
} as const;

/**
 * SiloV2 Pool Addresses (Sonic Chain)
 */
export const SILOV2_POOLS = {
  'wstkscUSD-USDC-23': '0x5954ce6671d97d24b782920ddcdbb4b1e63ab2de' as Address,
  'x33-USDC-49': '0xa18a8f100f2c976044f2f84fae1ee9f807ae7893' as Address,
  'Anon-USDC-27': '0x7e88ae5e50474a48dea4c42a634aa7485e7caa62' as Address,
  'S-USDC-20': '0x322e1d5384aa4ed66aeca770b95686271de61dc3' as Address,
  'PT-wstkscUSD (29 May)-USDC-34': '0x6030aD53d90ec2fB67F3805794dBB3Fa5FD6Eb64' as Address,
  'stS-USDC-36': '0x11Ba70c0EBAB7946Ac84F0E6d79162b0cBb2693f' as Address,
  'EGGS-USDC-33': '0x42CE2234fd5a26bF161477a996961c4d01F466a3' as Address,
  'S-USDC-8': '0x4E216C15697C1392fE59e1014B009505E05810Df' as Address,
  'wstkscUSD-USDC-55': '0x4935FaDB17df859667Cc4F7bfE6a8cB24f86F8d0' as Address,
  'Varlamore USDC Growth': '0xF6F87073cF8929C206A77b0694619DC776F89885' as Address,
  'Apostro - USDC': '0xcca902f2d3d265151f123d8ce8FdAc38ba9745ed' as Address,
  'Re7 scUSD': '0x592D1e187729C76EfacC6dfFB9355bd7BF47B2a7' as Address,
  'Greenhouse USDC': '0xf6bC16B79c469b94Cdd25F3e2334DD4FEE47A581' as Address,
} as const;

/**
 * SiloV2 Router and RewardsClaimer Addresses (Sonic Chain)
 */
export const SILOV2_ROUTER = '0x22aacdec57b13911de9f188cf69633cc537bdb76' as Address;
export const SILOV2_REWARDS_CLAIMERS = [
  '0xfFd019f29b068BCec229Ad352bA8346814BCfF72' as Address,
  '0x306Fad9009b104a323A232238afffD1f261bD05c' as Address,
  '0xB5073fC0dff2142FDdbb548e749B5acf259d4807' as Address,
] as const;

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
  
  // SiloV2 functions
  SILOV2_ROUTER_EXECUTE: '0xc3cd3eda' as `0x${string}`, // execute((uint8,address,address,bytes)[])
  SILO_CLAIM_REWARDS: '0xef5cfb8c' as `0x${string}`, // claimRewards(address)
  
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
    target: TOKENS.USDCe,
    selector: SELECTORS.ERC20_APPROVE,
    description: "USDC.e approve()",
  },
  {
    target: TOKENS.USDCe,
    selector: SELECTORS.ERC20_TRANSFER,
    description: "USDC.e transfer()",
  },
  
  // ========================================
  // AAVE POOL FUNCTIONS
  // ========================================
  {
    target: AAVE_POOLS.USDCe,
    selector: SELECTORS.AAVE_SUPPLY,
    description: "AAVE Pool USDC.e - supply()",
  },
  {
    target: AAVE_POOLS.USDCe,
    selector: SELECTORS.AAVE_WITHDRAW,
    description: "AAVE Pool USDC.e - withdraw()",
  },
  
  // ========================================
  // EULER POOL FUNCTIONS
  // ========================================
  {
    target: EULER_POOLS['MEV Capital Sonic Cluster USDC.e'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Euler MEV Capital Sonic Cluster USDC.e - deposit()",
  },
  {
    target: EULER_POOLS['MEV Capital Sonic Cluster USDC.e'],
    selector: SELECTORS.REDEEM,
    description: "Euler MEV Capital Sonic Cluster USDC.e - redeem()",
  },
  {
    target: EULER_POOLS['Re7 Labs Cluster USDC.e'],
    selector: SELECTORS.ERC4626_DEPOSIT,
    description: "Euler Re7 Labs Cluster USDC.e - deposit()",
  },
  {
    target: EULER_POOLS['Re7 Labs Cluster USDC.e'],
    selector: SELECTORS.REDEEM,
    description: "Euler Re7 Labs Cluster USDC.e - redeem()",
  },
  
  // ========================================
  // SILOV2 ROUTER (Sonic)
  // ========================================
  {
    target: SILOV2_ROUTER,
    selector: SELECTORS.SILOV2_ROUTER_EXECUTE,
    description: "SiloV2 Router (Sonic) - execute()",
  },
  
  // ========================================
  // SILOV2 VAULT FUNCTIONS (Sonic)
  // ========================================
  {
    target: SILOV2_POOLS['wstkscUSD-USDC-23'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 wstkscUSD-USDC-23 - redeem()",
  },
  {
    target: SILOV2_POOLS['x33-USDC-49'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 x33-USDC-49 - redeem()",
  },
  {
    target: SILOV2_POOLS['Anon-USDC-27'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 Anon-USDC-27 - redeem()",
  },
  {
    target: SILOV2_POOLS['S-USDC-20'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 S-USDC-20 - redeem()",
  },
  {
    target: SILOV2_POOLS['PT-wstkscUSD (29 May)-USDC-34'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 PT-wstkscUSD (29 May)-USDC-34 - redeem()",
  },
  {
    target: SILOV2_POOLS['stS-USDC-36'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 stS-USDC-36 - redeem()",
  },
  {
    target: SILOV2_POOLS['EGGS-USDC-33'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 EGGS-USDC-33 - redeem()",
  },
  {
    target: SILOV2_POOLS['S-USDC-8'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 S-USDC-8 - redeem()",
  },
  {
    target: SILOV2_POOLS['wstkscUSD-USDC-55'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 wstkscUSD-USDC-55 - redeem()",
  },
  {
    target: SILOV2_POOLS['Varlamore USDC Growth'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 Varlamore USDC Growth - redeem()",
  },
  {
    target: SILOV2_POOLS['Apostro - USDC'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 Apostro - USDC - redeem()",
  },
  {
    target: SILOV2_POOLS['Re7 scUSD'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 Re7 scUSD - redeem()",
  },
  {
    target: SILOV2_POOLS['Greenhouse USDC'],
    selector: SELECTORS.REDEEM,
    description: "SiloV2 Greenhouse USDC - redeem()",
  },
  
  // ========================================
  // SILOV2 REWARDS CLAIMERS (Sonic)
  // ========================================
  {
    target: SILOV2_REWARDS_CLAIMERS[0],
    selector: SELECTORS.SILO_CLAIM_REWARDS,
    description: "SiloV2 RewardsClaimer (Sonic) #1 - claimRewards()",
  },
  {
    target: SILOV2_REWARDS_CLAIMERS[1],
    selector: SELECTORS.SILO_CLAIM_REWARDS,
    description: "SiloV2 RewardsClaimer (Sonic) #2 - claimRewards()",
  },
  {
    target: SILOV2_REWARDS_CLAIMERS[2],
    selector: SELECTORS.SILO_CLAIM_REWARDS,
    description: "SiloV2 RewardsClaimer (Sonic) #3 - claimRewards()",
  },
  
  // ========================================
  // MERKL DISTRIBUTOR (Sonic)
  // ========================================
  {
    target: '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae' as Address,
    selector: SELECTORS.MERKL_CLAIM,
    description: "Merkl Distributor (Sonic) - claim()",
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

