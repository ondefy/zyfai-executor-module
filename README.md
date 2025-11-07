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
- **Time-Delayed Whitelist Management**: Whitelist changes require a 1-day timelock for security
- **Emergency Pause**: Module can be paused immediately if session keys are compromised
- **Upgradeable**: UUPS upgradeable pattern allows fixing bugs and adding features
- **Batch Operations**: Execute multiple operations in a single transaction for gas efficiency

### Security Model

1. **Whitelist Validation**: Every execution checks if the target+selector is whitelisted
2. **ERC20 Transfer Authorization**: ERC20 transfers are only allowed to:
   - The smart wallet itself
   - Wallet owners
   - Explicitly authorized recipients (e.g., DEX routers, lending protocols)
3. **Timelock Protection**: Whitelist changes require 1-day delay (can be cancelled if incorrect)
4. **Pausable**: Emergency stop capability for compromised session keys
5. **Permissionless Execution**: After timelock, anyone can execute scheduled operations (prevents censorship)

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
- Cannot directly whitelist target+selector (must go through timelock)
- Cannot execute operations directly through the module (must use session keys or smart account directly)

### 2. Registry Owner
**Role**: Controls the TargetRegistry contract
**Capabilities**:
- Schedule whitelist additions/removals (subject to 1-day timelock)
- Cancel pending whitelist operations
- Add/remove authorized ERC20 token recipients (immediate)
- Pause/unpause the registry (emergency stop)

**Limitations**:
- Cannot execute scheduled operations immediately (must wait 1 day)
- Cannot bypass timelock delay

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

### 4. Anyone (Permissionless Executor)
**Role**: Can execute scheduled whitelist operations after timelock expires
**Capabilities**:
- Execute scheduled whitelist additions/removals after 1-day delay
- Prevents censorship of legitimate whitelist changes

**Limitations**:
- Cannot execute operations before timelock expires
- Cannot schedule operations
- Cannot cancel operations

## 📁 Contract Architecture

### Contracts Overview

1. **GuardedExecModuleUpgradeable** (`src/module/GuardedExecModuleUpgradeable.sol`)
   - Main executor module contract
   - Implements ERC-7579 executor interface
   - Validates whitelist and ERC20 transfer authorization
   - Upgradeable via UUPS pattern

2. **TargetRegistry** (`src/registry/TargetRegistry.sol`)
   - Manages whitelist of target+selector combinations
   - Implements timelock for whitelist changes
   - Manages ERC20 transfer recipient authorization
   - Uses OpenZeppelin TimelockController

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
    │                   ├──> TimelockController (Time-Delayed Changes)
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
   - Registry owner calls `scheduleAdd()` or `scheduleRemove()` on TargetRegistry
   - Operation is scheduled via TimelockController (1-day delay)
   - After 1 day, anyone can call `executeOperation()` to finalize the change
   - Owner can cancel pending operations via `cancelOperation()`

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
forge test --match-test test_ScheduleAndExecuteAdd -vv

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
- **Test Status**: All 31 tests passing ✅

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
| `GuardedExecModuleUpgradeable.sol` | 98.11% | 88.00% | 40.00% | 92.86% |
| `TargetRegistry.sol` | 91.34% | 79.43% | 25.81% | 92.00% |

### Test Files

- `test/GuardedExecModuleUpgradeableTest.t.sol`: 19 tests
- `test/TargetRegistryTest.t.sol`: 12 tests

### Test Categories

- ✅ Whitelist validation tests
- ✅ ERC20 transfer authorization tests
- ✅ Timelock operation tests
- ✅ Pause/unpause tests
- ✅ Upgrade tests
- ✅ Batch operation tests
- ✅ Edge cases and error conditions

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

### Deploy Scripts

```bash
# Deploy TargetRegistry
PRIVATE_KEY=<key> forge script script/1-DeployTargetRegistry.s.sol \
    --rpc-url <rpc-url> \
    --broadcast -vvvv

# Upgrade and update module
TARGET_REGISTRY_ADDRESS=<address> forge script script/2-UpgradeAndUpdateModule.s.sol \
    --rpc-url <rpc-url> \
    --private-key <key> \
    --broadcast -vvvv
```

### Contract Verification

```bash
# Verify TargetRegistry
forge verify-contract <ADDRESS> src/registry/TargetRegistry.sol:TargetRegistry \
    --rpc-url <rpc-url> \
    --chain-id <chain-id> \
    --compiler-version 0.8.30 \
    --etherscan-api-key <key> \
    --constructor-args <encoded-args>

# Verify GuardedExecModuleUpgradeable
forge verify-contract <ADDRESS> src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable \
    --rpc-url <rpc-url> \
    --chain-id <chain-id> \
    --compiler-version 0.8.30 \
    --etherscan-api-key <key>
```

## 🔒 Security Considerations

### Timelock Delay

- **Current Setting**: 1 day (86400 seconds)
- **Purpose**: Provides window to cancel malicious or incorrect whitelist changes
- **For Production**: Consider increasing to 24-48 hours for higher security

### Access Control

- **Module Owner**: Can pause/unpause and upgrade (should be multisig)
- **Registry Owner**: Can schedule whitelist changes (should be multisig)
- **Session Keys**: Can only execute whitelisted operations

### Emergency Procedures

1. **Compromised Session Key**: Pause the module immediately via `pause()`
2. **Malicious Whitelist Change**: Cancel the operation via `cancelOperation()`
3. **Critical Vulnerability**: Pause both module and registry

## 📚 Additional Resources

- [ERC-7579 Standard](https://eips.ethereum.org/EIPS/eip-7579)
- [OpenZeppelin TimelockController](https://docs.openzeppelin.com/contracts/4.x/api/governance#TimelockController)
- [ModuleKit Documentation](https://docs.rhinestone.wtf/modulekit/)

## 📄 License

MIT

## 👥 Authors

ZyFAI

---

**Note**: This protocol is designed for production use with proper access control (multisig wallets) and appropriate timelock delays. Always conduct security audits before deploying to mainnet.
