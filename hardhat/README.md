# GuardedExecModule Integration Tests for Base Network

This directory contains comprehensive integration tests and deployment scripts for the GuardedExecModule on Base network, including Safe smart account creation, module installation, and session key management using Rhinestone SDK.

## 🚀 Quick Start

### Prerequisites

1. **Node.js** (v18 or higher)
2. **pnpm** (recommended) or npm
3. **Base RPC URL** (Alchemy, Infura, etc.)
4. **Private key** with Base ETH for deployment
5. **Rhinestone API key** (optional, for advanced features)

### Setup

1. **Install dependencies:**
   ```bash
   cd rhinestone
   pnpm install
   ```

2. **Configure environment:**
   ```bash
   cp env.base .env
   # Edit .env with your Base RPC URL and private key
   ```

3. **Compile contracts:**
   ```bash
   pnpm compile
   ```

4. **Deploy and test (full flow):**
   ```bash
   # Run complete setup and test
   pnpm run full-setup
   ```

5. **Or run individual steps:**
   ```bash
   # Deploy contracts to Base
   pnpm run deploy:base
   
   # Create Safe smart account
   pnpm run create-safe-account
   
   # Install GuardedExecModule
   pnpm run install-module
   
   # Setup whitelist
   pnpm run setup-whitelist
   
   # Create session key
   pnpm run create-session-key
   
   # Test integration
   pnpm run test-integration
   ```

## 📁 Project Structure

```
rhinestone/
├── contracts/              # Solidity contracts
│   ├── GuardedExecModule.sol
│   ├── TargetRegistry.sol
│   └── ISafeWallet.sol
├── scripts/                # Deployment and setup scripts
│   ├── deploy.ts
│   └── setup-whitelist.ts
├── test/                   # Integration tests
│   ├── e2e-aave-integration.test.ts
│   └── mock-smart-account.sol
├── package.json
├── hardhat.config.ts
└── README.md
```

## 🧪 Test Coverage

### E2E AAVE Integration Tests

- **AAVE Supply**: Session key supplies USDC to AAVE V3
- **AAVE Withdraw**: Session key withdraws from AAVE V3
- **ERC20 Restrictions**: USDC transfers restricted to smart account owners
- **Security Tests**: Non-whitelisted operations blocked
- **Pause Tests**: Module pause functionality

### Test Scenarios

1. **Happy Path**:
   - Deploy contracts
   - Setup whitelist with timelock
   - Create smart account with GuardedExecModule
   - Execute AAVE operations via session key

2. **Security Tests**:
   - Block non-whitelisted operations
   - Block unauthorized ERC20 transfers
   - Test pause functionality

3. **Edge Cases**:
   - Timelock not ready
   - Insufficient token balance
   - Invalid calldata

## 🔧 Configuration

### Environment Variables

```bash
# Required
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY

# Optional
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=0x1234567890abcdef...
```

### Hardhat Configuration

The tests use Hardhat's mainnet forking feature to interact with real contracts:

```typescript
// hardhat.config.ts
networks: {
  hardhat: {
    forking: {
      url: process.env.MAINNET_RPC_URL,
      blockNumber: 19000000, // Pin to specific block
    },
  },
}
```

## 🏗️ Deployment Scripts

### Deploy Contracts

```bash
# Deploy to local fork
pnpm run deploy

# Deploy to Sepolia testnet
npx hardhat run scripts/deploy.ts --network sepolia
```

### Setup Whitelist

```bash
# Setup whitelist for testing
REGISTRY_ADDRESS=0x... pnpm run setup-whitelist
```

## 🧪 Running Tests

### All Tests

```bash
pnpm test
```

### Specific Test Suites

```bash
# E2E tests only
pnpm test:e2e

# With verbose output
pnpm test -- --reporter spec

# Run specific test
pnpm test -- --grep "AAVE Integration"
```

### Fork Mainnet

```bash
# Start local fork
pnpm run fork:mainnet

# In another terminal, run tests
pnpm test
```

## 📊 Test Results

Expected test output:

```
🚀 Setting up E2E test environment...
📋 Deploying contracts...
✅ TargetRegistry deployed to: 0x...
✅ GuardedExecModule deployed to: 0x...
✅ Smart Account deployed to: 0x...

🧪 Testing AAVE supply via session key...
✅ Transaction successful: 0x...

🧪 Testing AAVE withdraw via session key...
✅ Withdraw transaction successful: 0x...

🧪 Testing USDC transfer to smart account owner...
✅ Transfer transaction successful: 0x...

🧪 Testing USDC transfer to unauthorized address...
✅ Transfer to unauthorized address blocked

🧪 Testing non-whitelisted operation...
✅ Non-whitelisted operation blocked

🧪 Testing paused module...
✅ Paused module blocked operations

✅ All tests passed!
```

## 🔍 Debugging

### Common Issues

1. **RPC Rate Limits**: Use a premium RPC provider
2. **Block Number**: Update `blockNumber` in hardhat.config.ts
3. **Token Balances**: Check if USDC holder has sufficient balance
4. **Timelock**: Ensure 24-hour delay has passed

### Debug Commands

```bash
# Compile with debug info
pnpm compile --force

# Run with debug logs
DEBUG=hardhat* pnpm test

# Check contract state
npx hardhat console --network hardhat
```

## 🚀 Production Deployment

For production deployment:

1. **Deploy to mainnet**:
   ```bash
   npx hardhat run scripts/deploy.ts --network mainnet
   ```

2. **Verify contracts**:
   ```bash
   npx hardhat verify --network mainnet <CONTRACT_ADDRESS>
   ```

3. **Setup whitelist**:
   ```bash
   REGISTRY_ADDRESS=0x... npx hardhat run scripts/setup-whitelist.ts --network mainnet
   ```

## 📝 Notes

- Tests use mainnet forking for realistic testing
- Session keys are simulated (not real cryptographic signatures)
- Mock smart account is used instead of full ERC-7579 implementation
- All tests run on local fork by default

## 🤝 Contributing

1. Add new test cases in `test/` directory
2. Update deployment scripts in `scripts/` directory
3. Follow existing naming conventions
4. Add proper error handling and logging
5. Update README with new features
