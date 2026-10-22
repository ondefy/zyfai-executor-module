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
3. **ERC20 Approve Authorization**: The spender of an ERC20 `approve` must be a whitelisted target (a trusted contract such as the Zyfai Adapter or a protocol pool). A zero-amount `approve` only clears an allowance, so it is allowed for any spender, including one removed from the registry
4. **Authorization Grant Validation**: For Morpho Blue `setAuthorization(address,bool)` (`0xeecea000`) and ERC-7540 `setOperator(address,bool)` (`0x558a7297`), a grant (`true`) must name the Zyfai Adapter (`ADAPTER`). Any other grantee reverts, including other whitelisted targets. A revoke (`false`) is always allowed for any address, so a stale grant can always be removed. `ADAPTER` is an immutable set in the implementation constructor (prod: `0xaffD3c3cD06cf499deddf78b26868018A93f2C31` on Ethereum, Base and Arbitrum). It is fixed per implementation deployment: changing it requires deploying a new implementation and upgrading the module proxy
5. **Aave v4 Spoke Health Factor**: After a batch that calls `borrow` (`0xd6bda0c0`), `withdraw` (`0x0ad58d2f`) or `setUsingAsCollateral` (`0x9e35c533`) on a target, the module reads `getUserAccountData(smartAccount).healthFactor` on that target and reverts the whole batch if it is below 1.5 (`MIN_HEALTH_FACTOR`, WAD). The Spoke itself only enforces 1.0, so this stops a session key from pushing the account to the edge of liquidation and liquidating it. These three selectors must only be whitelisted on Aave v4 Spokes
6. **IPOR Request Fee**: IPOR Fusion WithdrawManager `requestShares(uint256)` (`0xfc415e9c`) takes its fee from the smart account's vault shares with no cap or approval, and each request overwrites the last. While the target's `getRequestFee()` is non-zero, a request must not exceed the smart account's vault shares, must not replace a request whose withdraw window is still open, must be the only one to that WithdrawManager in the batch, the fee must be at most 1% and the withdraw window at least 1 day. A session key can then cost at most 1% of the position per vault per day. At fee 0 the call is unrestricted. This selector must only be whitelisted on IPOR WithdrawManagers
7. **Owner-Controlled Whitelist**: Only contract owner can modify whitelist (should be multisig for production)
8. **Pausable**: Emergency stop capability for compromised session keys or malicious whitelist changes
9. **Two-Step Ownership Transfer**: Prevents accidental or malicious ownership transfers

### Selectors that must never be whitelisted

These calls would let a session key bypass the checks above:

- Aave v4 Spoke: `setUserPositionManager` (`0x8874e104`), `setUserPositionManagersWithSig` (`0x03ed05c1`), `multicall` (`0xac9650d8`), `liquidationCall`, `updateUserDynamicConfig` (`0x826002e2`)
- Any protocol's operator/delegate/authorization grant that is not validated above (only `0xeecea000` and `0x558a7297` are checked)

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
- Approve ERC20 spending to whitelisted targets only
- Grant protocol authorizations/operators to the Adapter only
- Borrow on an Aave v4 Spoke while keeping the account health factor at or above 1.5

**Limitations**:
- Cannot execute operations on non-whitelisted target+selectors
- Cannot transfer ERC20 tokens to arbitrary addresses
- Cannot approve a non-whitelisted address
- Cannot authorize or make an operator of any address other than the Adapter
- Cannot leave an Aave v4 Spoke position below a 1.5 health factor
- Cannot pause the module
- Cannot modify the whitelist
- Cannot upgrade the module


## 📁 Contract Architecture

### Contracts Overview

1. **GuardedExecModuleUpgradeable** (`src/module/GuardedExecModuleUpgradeable.sol`)
   - Main executor module contract
   - Implements ERC-7579 executor interface
   - Validates whitelist, ERC20 transfer/approve authorization, authorization grants, and Aave v4 Spoke health factor
   - Upgradeable via UUPS pattern

2. **TargetRegistry** (`src/registry/TargetRegistry.sol`)
   - Manages whitelist of target+selector combinations
   - Owner-controlled whitelist management (immediate changes)
   - Manages ERC20 transfer recipient authorization
   - Pausable for emergency stops

3. **ISafeWallet** (`src/interfaces/ISafeWallet.sol`)
   - Interface for querying smart wallet owners
   - Used for ERC20 transfer authorization checks

4. **IAaveV4Spoke** (`src/interfaces/IAaveV4Spoke.sol`)
   - Minimal Aave v4 Spoke interface (`getUserAccountData`) used for the health factor check

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
   - Module validates ERC20 approve spenders against whitelisted targets, and requires `setAuthorization` / `setOperator` grantees to be the Adapter
   - Module executes batch operations via smart account (maintains context)
   - If the batch called `borrow`, `withdraw` or `setUsingAsCollateral` on a Spoke, the module checks the account health factor on that Spoke after execution

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

// 2. Deploy module implementation (adapter = the only setAuthorization/setOperator grantee)
GuardedExecModuleUpgradeable implementation = new GuardedExecModuleUpgradeable(adapter);

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
# All module deploy/upgrade scripts read the implementation constructor arg from
# ADAPTER_ADDRESS (prod: 0xaffD3c3cD06cf499deddf78b26868018A93f2C31). Verifying a new
# implementation needs --constructor-args $(cast abi-encode "constructor(address)" $ADAPTER_ADDRESS)

# Deploy ERC1967 module
ADAPTER_ADDRESS=<Adapter-Address> PRIVATE_KEY=pk forge script script/0-DeployUpgradeableSimple.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --broadcast -vvvv

# Deploy TargetRegistry
PRIVATE_KEY=pk forge script script/1-DeployTargetRegistry.s.sol --rpc-url https://sonic-mainnet.g.alchemy.com/v2/key --broadcast -vvvv

# Verify TargetRegistry
forge verify-contract <Registry-Address> src/registry/TargetRegistry.sol:TargetRegistry --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key --constructor-args 0x000000000000000000000000d61C43c089852e0AB68B967dD1eDe03a18e52223

# Upgrade Module
ADAPTER_ADDRESS=<Adapter-Address> TARGET_REGISTRY_ADDRESS=<Registry-Address> forge script script/2-UpgradeAndUpdateModule.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --private-key pk --broadcast -vvvv

# Verify New Impl of Module
forge verify-contract <NEW-IMPL-Address> src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key

# Proxy Verify
forge verify-contract <NEW-IMPL-Address> lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --constructor-args 0x000000000000000000000000079c22bbd7b5b91bde24687036d3d3ee2b6c634c00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000044485cc955000000000000000000000000a0bee327a95f786f5097028ee250c4834dfeb629000000000000000000000000d61c43c089852e0ab68b967dd1ede03a18e5222300000000000000000000000000000000000000000000000000000000 --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key

forge verify-contract \
  0xf8DAAe25b9388762eb24e83324d9f4ec46c000fc \
  src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable \
  --rpc-url https://arb-mainnet.g.alchemy.com/v2/key \
  --chain-id 42161 \
  --compiler-version 0.8.30 \
  --etherscan-api-key key

# for Arb
forge verify-contract \
  0xF659d30D4EB88B06A909F20839D8959Bd77d8790 \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args \
  0x000000000000000000000000d5C2dFD6d34c2bEA1dbec14DE4780d4A9D45ea1700000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/key \
  --chain-id 1 \
  --compiler-version 0.8.30 \
  --etherscan-api-key key

forge script script/DeployWithCREATE3.s.sol:DeployWithCREATE3 \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/key \
  --broadcast \
  -vvvv

# Final Command

PRIVATE_KEY=pk forge script script/1-DeployTargetRegistry.s.sol --rpc-url https://sonic-mainnet.g.alchemy.com/v2/key --broadcast -vvvv

forge script script/DeployWithCREATE3.s.sol:DeployWithCREATE3 \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/key \
  --broadcast \
  -vvvv

forge verify-contract \
  <TARGET_REGISTRY_ADDRESS> \
  src/registry/TargetRegistry.sol:TargetRegistry \
  --rpc-url https://base-mainnet.g.alchemy.com/v2/key \
  --chain-id 8453 \
  --compiler-version 0.8.30 \
  --etherscan-api-key etherscan-key \
  --constructor-args 0x000000000000000000000000d61C43c089852e0AB68B967dD1eDe03a18e52223

forge verify-contract \
    <MODULE_IMPL_ADDRESS> \
    src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable \
    --rpc-url https://base-mainnet.g.alchemy.com/v2/key \
    --chain-id 8453 \
    --compiler-version 0.8.30 \
    --etherscan-api-key etherscan-key

forge verify-contract \
  <MODULE_PROXY_ADDRESS> \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args \
  0x000000000000000000000000c8F535f56C191D4D623e252D540BA1Fcb656120800000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url https://base-mainnet.g.alchemy.com/v2/key \
  --chain-id 8453 \
  --compiler-version 0.8.30 \
  --etherscan-api-key etherscan-key


# For plasma
forge verify-contract \
  0xc8F535f56C191D4D623e252D540BA1Fcb6561208 \
  src/registry/TargetRegistry.sol:TargetRegistry \
  --rpc-url https://plasma-mainnet.g.alchemy.com/v2/key \
  --chain-id 9745 \
  --compiler-version 0.8.30 \
  --verifier custom \
  --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/9745/etherscan' \
  --verifier-api-key "verifyContract" \
  --constructor-args 0x000000000000000000000000d61C43c089852e0AB68B967dD1eDe03a18e52223

forge verify-contract \
  0xA49EA89806c53966f12920d12F1B484C63E43AEA \
  src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable \
  --rpc-url https://plasma-mainnet.g.alchemy.com/v2/key \
  --chain-id 9745 \
  --compiler-version 0.8.30 \
  --verifier custom \
  --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/9745/etherscan' \
  --verifier-api-key "verifyContract"
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
