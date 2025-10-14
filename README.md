# GuardedExecModule - Two Implementation Approaches

This repository contains **two different implementation approaches** for a session key-enabled DeFi executor module for ERC-7579 smart accounts.

## Project Structure

```
rhinestone-executor-module/
├── src/
│   ├── delegatecall-approach/    # Approach 1: Module + Router (2 contracts)
│   └── unified-approach/          # Approach 2: Unified Module (1 contract) RECOMMENDED
├── test/
│   ├── delegatecall-approach/
│   └── unified-approach/
```

## Quick Start

### Run Tests
```bash
# Test both approaches
forge test

# Test unified approach only (RECOMMENDED)
forge test --match-path "test/unified-approach/*"

# Test delegatecall approach only
forge test --match-path "test/delegatecall-approach/*"

# Run all tests
forge test --match-path test/unified-approach/GuardedExecModule.t.sol -vv

# Run specific test
forge test --match-test test_UnifiedApproach_MsgSenderIsSmartAccount -vv

# Gas report
forge test --match-path test/unified-approach/GuardedExecModule.t.sol --gas-report
```

## Recommended: Unified Approach

**Use**: `src/unified-approach/GuardedExecModule.sol`

### Why?
- **23-45% lower gas costs** (users save $5k+/year)
- **Simpler architecture** (1 contract vs 2)
- **Equal security guarantees**
- **Production-ready** code


## Comparison

| Feature | Delegatecall | Unified |
|---------|--------------|---------|
| Gas (3 calls) | 412,280 | 255,611 (**38% cheaper**) |
| Contracts | 2 | 1 |
| msg.sender | Smart Account | Smart Account |
| Recommended | Platform use | **Single module** |


## Quick Deploy (Unified)

```solidity
// 1. Deploy registry
TargetRegistry registry = new TargetRegistry(owner);

// 2. Deploy module
GuardedExecModule module = new GuardedExecModule(address(registry));

// 3. Install on smart account
smartAccount.installModule(MODULE_TYPE_EXECUTOR, module, "");
```
