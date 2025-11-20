# GuardedExecModule

A secure executor module for smart accounts that enables session keys to execute whitelisted DeFi operations while maintaining smart account security through whitelist validation and ERC20 transfer restrictions.

## 📖 ELI5: What is This?

Imagine you have a smart wallet (like a digital safe) that holds your crypto. You want to let a friend use it to do specific things, like swap tokens on Uniswap or deposit into Aave, but you don't want them to be able to withdraw all your money or send it to random addresses.

This protocol is like giving your friend a special key that:
- ✅ Can only do things you've pre-approved (like "swap tokens on Uniswap")
- ✅ Can't send your tokens to random people
- ✅ Can only send tokens to safe places (your wallet, back to you, or trusted protocols)
- ✅ You can turn off immediately if needed (pause functionality)

The "whitelist" is like a list of approved actions. Before the friend can do anything, the system checks: "Is this action on the approved list?" If yes, it's allowed. If no, it's blocked.

## 🎯 High-Level Description

GuardedExecModule is an ERC-7579 executor module that provides secure, whitelisted execution capabilities for smart accounts. It enables session keys (limited-authority keys) to execute batch operations on whitelisted DeFi protocols while maintaining the security and context of the smart account.

### Key Features

- **Whitelist-Based Execution**: Only pre-approved target contract + function selector combinations can be executed
- **ERC20 Transfer Restrictions**: Prevents arbitrary token transfers; only allows transfers to authorized recipients
- **Direct Whitelist Management**: Owner can directly add/remove whitelisted targets and selectors
- **Emergency Pause**: Module and registry can be paused immediately if session keys are compromised
- **Upgradeable**: UUPS upgradeable pattern allows fixing bugs and adding features
- **Batch Operations**: Execute multiple operations in a single transaction for gas efficiency

### Security Model

1. **Whitelist Validation**: Every execution checks if the target+selector is whitelisted
2. **ERC20 Transfer Authorization**: ERC20 transfers are only allowed to:
   - The smart wallet itself
   - Wallet owners
   - Explicitly authorized recipients (e.g., DEX routers, lending protocols)
3. **Owner-Controlled Whitelist**: Only contract owner can modify whitelist (should be multisig for production)
4. **Pausable**: Emergency stop capability for compromised session keys or malicious whitelist changes
5. **Two-Step Ownership Transfer**: Prevents accidental or malicious ownership transfers

## 👥 Actors and Roles

### 1. Smart Account Owner
**Role**: Primary controller of the smart account
**Capabilities**:
- Install/uninstall the GuardedExecModule on their smart account
- Own the TargetRegistry (if they deploy it)
- Pause/unpause the module if session key is compromised
- Upgrade the module (if owner of module)
- Update registry address (if owner of module)

**Limitations**:
- Cannot execute operations directly through the module (must use session keys or smart account directly)

### 2. Registry Owner
**Role**: Controls the TargetRegistry contract
**Capabilities**:
- Add/remove whitelisted target+selector combinations (immediate)
- Add/remove authorized ERC20 token recipients (immediate)
- Pause/unpause the registry (emergency stop)
- Transfer ownership (two-step process)

**Limitations**:
- Cannot modify whitelist when registry is paused
- Cannot modify ERC20 recipient authorization when registry is paused

### 3. Session Key
**Role**: Limited-authority key that can execute whitelisted operations
**Capabilities**:
- Execute batch operations on whitelisted target+selector combinations
- Execute operations that maintain smart account context (msg.sender = smart account)
- Execute ERC20 transfers to authorized recipients only

**Limitations**:
- Cannot execute operations on non-whitelisted target+selectors
- Cannot transfer ERC20 tokens to arbitrary addresses
- Cannot pause the module
- Cannot modify the whitelist
- Cannot upgrade the module


## 📁 Contract Architecture

### Contracts Overview

1. **GuardedExecModuleUpgradeable** (`src/module/GuardedExecModuleUpgradeable.sol`)
   - Main executor module contract
   - Implements ERC-7579 executor interface
   - Validates whitelist and ERC20 transfer authorization
   - Upgradeable via UUPS pattern

2. **TargetRegistry** (`src/registry/TargetRegistry.sol`)
   - Manages whitelist of target+selector combinations
   - Owner-controlled whitelist management (immediate changes)
   - Manages ERC20 transfer recipient authorization
   - Pausable for emergency stops

3. **ISafeWallet** (`src/interfaces/ISafeWallet.sol`)
   - Interface for querying smart wallet owners
   - Used for ERC20 transfer authorization checks

### Contract Relationships

```
Smart Account
    │
    ├──> GuardedExecModuleUpgradeable (Executor Module)
    │         │
    │         └──> TargetRegistry (Whitelist Verification)
    │                   │
    │                   └──> ISafeWallet (Owner Query for ERC20 Auth)
    │
    └──> Session Keys (Execute via Module)
```

### Data Flow

1. **Execution Flow**:
   - Session key calls `executeGuardedBatch()` on GuardedExecModuleUpgradeable
   - Module validates all target+selector combinations against TargetRegistry whitelist
   - Module validates ERC20 transfers (if any) against authorized recipients
   - Module executes batch operations via smart account (maintains context)

2. **Whitelist Management Flow**:
   - Registry owner calls `addToWhitelist()` or `removeFromWhitelist()` on TargetRegistry
   - Changes take effect immediately (if registry is not paused)
   - Owner can pause the registry to prevent any whitelist modifications

## 🏗️ Building and Compiling

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest version)
- Node.js and pnpm (for Hardhat scripts, if needed)

### Installation

```bash
# Clone the repository
git clone https://github.com/ondefy/zyfai-executor-module.git
cd rhinestone-executor-module

# Install dependencies (if using pnpm)
pnpm install

# Install Foundry dependencies
forge install
```

### Compile

```bash
# Compile all contracts
forge build

# Compile with optimizations (for production)
FOUNDRY_PROFILE=optimized forge build
```

### Clean

```bash
# Remove build artifacts
forge clean
```

### Verification

The code should compile without errors or warnings. If warnings are present, they should be documented and explained.

## 🧪 Testing

### Run All Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vv

# Run with very verbose output (trace level)
forge test -vvv
```

### Run Specific Test Files

```bash
# Run TargetRegistry tests
forge test --match-path "test/TargetRegistryTest.t.sol"

# Run GuardedExecModuleUpgradeable tests
forge test --match-path "test/GuardedExecModuleUpgradeableTest.t.sol"
```

### Run Specific Tests

```bash
# Run a specific test function
forge test --match-test test_AddToWhitelist -vv

# Run tests matching a pattern
forge test --match-test "test_*ERC20*" -vv
```

### Test Coverage

**Important**: Test coverage must be >80% and all tests must pass.

```bash
# Generate coverage report (summary)
forge coverage --report summary

# Generate detailed LCOV coverage report
forge coverage --report lcov

# View coverage with minimum optimization (fixes "stack too deep" issues)
forge coverage --report summary --ir-minimum
```

### Coverage Requirements

- **Target Coverage**: >80% for all main contracts
- **Current Coverage**:
  - `GuardedExecModuleUpgradeable.sol`: 98.11% lines, 88.00% statements ✅
  - `TargetRegistry.sol`: 91.34% lines, 79.43% statements ✅
- **Test Status**: All 54 tests passing ✅

### Clean Environment Testing

To test in a clean environment (as required by Sherlock):

```bash
# 1. Clean all artifacts
forge clean
rm -rf cache out

# 2. Install dependencies
forge install
pnpm install  # if using Hardhat scripts

# 3. Build
forge build

# 4. Run tests
forge test

# 5. Check coverage
forge coverage --report summary
```

All tests should pass and coverage should be >80% in a clean environment.

## 📊 Test Coverage Details

### Current Coverage

| Contract | Lines | Statements | Branches | Functions |
|----------|-------|------------|----------|-----------|
| `GuardedExecModuleUpgradeable.sol` | **98.11%** (52/53) | **100.00%** (50/50) | **100.00%** (10/10) | **92.86%** (13/14) |
| `TargetRegistry.sol` | **91.34%** (116/127) | **89.36%** (126/141) | **70.97%** (22/31) | **92.00%** (23/25) |
| **Overall** | **94.44%** | **94.24%** | **82.93%** | **92.31%** |

### Test Files

- `test/GuardedExecModuleUpgradeableTest.t.sol`: 32 tests
- `test/TargetRegistryTest.t.sol`: 22 tests
- **Total**: 54 tests

### Test Categories

- ✅ Whitelist validation tests
- ✅ ERC20 transfer authorization tests
- ✅ Direct whitelist management tests
- ✅ Pause/unpause tests
- ✅ Upgrade tests
- ✅ Batch operation tests
- ✅ Two-step ownership transfer tests
- ✅ Edge cases and error conditions
- ✅ Input validation tests (empty batches, length mismatches)
- ✅ Invalid input tests (zero addresses, invalid selectors)
- ✅ Calldata validation tests (too short, malformed)
- ✅ Access control tests (owner-only functions)

### Test Quality Assurance

All tests follow Sherlock's requirement: **Every test has a way to fail**. Tests use:
- `vm.expectRevert()` - Tests will fail if the expected revert doesn't occur
- `assertTrue()`, `assertFalse()`, `assertEq()` - Tests will fail if assertions don't hold
- Error selector matching - Tests verify specific error types

## 📝 Code Commenting

All contracts have comprehensive natspec comments with >80% comment-to-code ratio:

- **TargetRegistry.sol**: 98.85% comment ratio
- **GuardedExecModuleUpgradeable.sol**: 124.79% comment ratio

Comments include:
- Contract-level documentation
- Function documentation with @notice, @dev, @param, @return
- Security considerations
- Gas optimization notes
- Inline comments for complex logic

## 🚀 Deployment

### Quick Deploy (Solidity)

```solidity
// 1. Deploy registry
TargetRegistry registry = new TargetRegistry(owner);

// 2. Deploy module implementation
GuardedExecModuleUpgradeable implementation = new GuardedExecModuleUpgradeable();

// 3. Deploy proxy and initialize
ERC1967Proxy proxy = new ERC1967Proxy(
    address(implementation),
    abi.encodeWithSelector(
        GuardedExecModuleUpgradeable.initialize.selector,
        address(registry),
        owner
    )
);

// 4. Install on smart account
smartAccount.installModule(MODULE_TYPE_EXECUTOR, address(proxy), "");
```

### 🚀 Deploy and Verify (one-liner cheatsheet)

```bash
# Deploy TargetRegistry
PRIVATE_KEY=pk-add-here forge script script/1-DeployTargetRegistry.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --broadcast -vvvv

# Verify TargetRegistry
forge verify-contract <TARGET_REGISTRY_ADDRESS> src/registry/TargetRegistry.sol:TargetRegistry --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key-add-here --constructor-args 0x000000000000000000000000<OWNER_ADDRESS>

# Upgrade Module
TARGET_REGISTRY_ADDRESS=0xFEe351d2Bf326AAfF9d4621c8BB2Ab7b2fe8780c forge script script/2-UpgradeAndUpdateModule.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --private-key pk --broadcast -vvvv

# Verify New Impl of Module
forge verify-contract <NEW_IMPL_ADDRESS> src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key

# Proxy Verify
forge verify-contract <PROXY_ADDRESS> lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --constructor-args 0x000000000000000000000000079c22bbd7b5b91bde24687036d3d3ee2b6c634c00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000044485cc955000000000000000000000000a0bee327a95f786f5097028ee250c4834dfeb629000000000000000000000000d61c43c089852e0ab68b967dd1ede03a18e5222300000000000000000000000000000000000000000000000000000000 --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key
```


## 🔒 Security Considerations

### Access Control

- **Module Owner**: Can pause/unpause and upgrade (should be multisig)
- **Registry Owner**: Can modify whitelist and ERC20 recipient authorization (should be multisig)
- **Session Keys**: Can only execute whitelisted operations
- **Two-Step Ownership**: Ownership transfers require explicit acceptance from new owner

### Emergency Procedures

1. **Compromised Session Key**: Pause the module immediately via `pause()`
2. **Malicious Whitelist Change**: Pause the registry immediately via `pause()` to prevent further changes
3. **Critical Vulnerability**: Pause both module and registry
4. **Incorrect Whitelist Addition**: Remove the entry immediately via `removeFromWhitelist()`

## 📚 Additional Resources

- [ERC-7579 Standard](https://eips.ethereum.org/EIPS/eip-7579)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [ModuleKit Documentation](https://docs.rhinestone.wtf/modulekit/)

## 📄 License

MIT

## 👥 Authors

ZyFAI

---

**Note**: This protocol is designed for production use with proper access control (multisig wallets for both module and registry owners). Always conduct security audits before deploying to mainnet.
