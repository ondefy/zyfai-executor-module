# Whitelist Management

This folder contains utilities and configuration for managing the TargetRegistry whitelist.

## Structure

```
whitelist/
├── data.ts       # Whitelist configuration (targets + selectors)
├── utils.ts      # Shared utility functions
└── README.md     # This file
```

## Usage

### 1. Configure Whitelist Items

Edit `data.ts` to define what you want to whitelist:

```typescript
export const whitelistConfig: WhitelistItem[] = [
  // Already whitelisted - comment out for history
  // { target: CONTRACTS.AAVE_POOL, selector: '0x...', description: "AAVE Pool supply()" },
  
  // New items to whitelist
  { target: CONTRACTS.NEW_TARGET, selector: '0x...', description: "New function" },
];
```

### 2. Add to Whitelist

Run script 4:
```bash
pnpm run whitelist-registry
# or
npx ts-node hardhat/scripts/4-whitelist-registry.ts
```

The script will:
- Check current status of all items in `data.ts`
- Only add items that are NOT already whitelisted
- Show detailed status before and after

### 3. Remove from Whitelist

Run script 5:
```bash
pnpm run remove-from-whitelist
# or
npx ts-node hardhat/scripts/5-remove-from-whitelist.ts
```

The script will:
- Check current status of all items in `data.ts`
- Only remove items that ARE currently whitelisted
- Show detailed status before and after

## Best Practices

1. **Maintain History**: Comment out items that are already whitelisted instead of deleting them
2. **Clear Descriptions**: Use descriptive strings for each item
3. **Group Related Items**: Group items by contract or functionality
4. **Test First**: Verify selectors before adding them to production

## Files

### `data.ts`

Contains:
- Contract addresses (Base chain)
- Whitelist configuration array
- Helper functions to extract targets and selectors

### `utils.ts`

Contains:
- TargetRegistry ABI
- Client creation utilities
- Status checking functions
- Display helpers

