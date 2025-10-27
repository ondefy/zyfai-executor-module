# 🚀 GuardedExecModule Deployment Guide for Base Network

This guide walks you through deploying the GuardedExecModule on Base network with Safe smart accounts and session key management.

## 📋 Overview

The integration test suite provides a complete end-to-end solution for:

1. **Contract Deployment**: Deploy `SimpleTargetRegistry` and `SimpleGuardedExecModule` on Base
2. **Safe Account Creation**: Create a Safe smart account using Rhinestone SDK
3. **Module Installation**: Install the GuardedExecModule on the Safe account
4. **Whitelist Setup**: Configure token and protocol whitelisting
5. **Session Key Management**: Create and configure session keys for automated execution
6. **Integration Testing**: Verify the complete flow works correctly

## 🔧 Prerequisites

### Required
- Node.js v18+
- pnpm package manager
- Base network RPC URL (Alchemy, Infura, etc.)
- Private key with Base ETH (at least 0.1 ETH for deployment and testing)

### Optional
- Rhinestone API key for advanced features
- Base ETH for gas fees

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Clone and navigate to integration-tests
cd integration-tests

# Install dependencies
pnpm install

# Copy environment template
cp env.base .env

# Edit .env with your configuration
nano .env
```

### 2. Configure Environment Variables

Edit `.env` file with your values:

```bash
# Base Network Configuration
BASE_RPC_URL=https://mainnet.base.org
BASE_PRIVATE_KEY=0x1234567890abcdef... # Your private key

# Rhinestone Configuration (optional)
RHINESTONE_API_KEY=your_rhinestone_api_key_here

# Contract Addresses (filled automatically)
TARGET_REGISTRY_ADDRESS=
GUARDED_EXEC_MODULE_ADDRESS=
SAFE_ACCOUNT_ADDRESS=

# Session Key Configuration (generated automatically)
SESSION_KEY_PRIVATE_KEY=
SESSION_KEY_VALID_UNTIL=

# Test Configuration
USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
WETH_ADDRESS=0x4200000000000000000000000000000000000006
```

### 3. Run Complete Setup

```bash
# Compile contracts
pnpm compile

# Run complete setup and test
pnpm run full-setup
```

This will:
1. Deploy contracts to Base
2. Create Safe smart account
3. Install GuardedExecModule
4. Setup whitelist
5. Create session key
6. Run integration tests

## 📝 Individual Scripts

### Deploy Contracts
```bash
pnpm run deploy:base
```
- Deploys `SimpleTargetRegistry` and `SimpleGuardedExecModule`
- Saves addresses to `.env` file
- Verifies contract deployment

### Create Safe Account
```bash
pnpm run create-safe-account
```
- Creates Safe smart account using Rhinestone SDK
- Funds account with 0.1 ETH
- Saves address to `.env` file

### Install Module
```bash
pnpm run install-module
```
- Installs GuardedExecModule on Safe account
- Verifies module installation
- Sets up module permissions

### Setup Whitelist
```bash
pnpm run setup-whitelist
```
- Whitelists USDC, WETH, DAI operations
- Sets up ERC20 transfer restrictions
- Configures token permissions

### Create Session Key
```bash
pnpm run create-session-key
```
- Generates session key wallet
- Funds with 0.01 ETH
- Saves configuration to `session-key.json`

### Test Integration
```bash
pnpm run test-integration
```
- Tests whitelist functionality
- Verifies ERC20 restrictions
- Tests session key permissions
- Validates security measures

## 🏗️ Architecture

### Contracts

1. **SimpleTargetRegistry**
   - Manages whitelist of target addresses and selectors
   - Handles ERC20 transfer restrictions
   - Immediate operations (no timelock for simplicity)

2. **SimpleGuardedExecModule**
   - Executes whitelisted operations
   - Enforces ERC20 transfer restrictions
   - Pausable for emergency stops

3. **MockSmartAccount**
   - Simulates ERC-7579 smart account
   - Integrates with GuardedExecModule
   - Supports session key execution

### Base Network Integration

- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- **WETH**: `0x4200000000000000000000000000000000000006`
- **DAI**: `0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb`

## 🔒 Security Features

### Whitelist Management
- Target address + function selector whitelisting
- Immediate add/remove operations
- Owner-only management

### ERC20 Transfer Restrictions
- Restricted token list (USDC, WETH)
- Transfer only to Safe account or owners
- Automatic validation on execution

### Session Key Security
- Limited permissions to GuardedExecModule
- Time-based expiration
- Owner-controlled generation

### Emergency Controls
- Module pause functionality
- Owner-only pause controls
- Immediate effect

## 🧪 Testing

### Integration Tests
- Whitelist verification
- ERC20 transfer authorization
- Module pause functionality
- Session key execution simulation
- Non-whitelisted operation blocking

### Test Coverage
- ✅ Contract deployment
- ✅ Safe account creation
- ✅ Module installation
- ✅ Whitelist configuration
- ✅ Session key generation
- ✅ Security validations

## 📊 Expected Output

### Successful Deployment
```
🚀 Starting deployment to Base network...
Deployer: 0x1234...5678
Deployer balance: 0.5 ETH

📋 Deploying SimpleTargetRegistry...
✅ SimpleTargetRegistry deployed to: 0xabcd...efgh

🛡️ Deploying SimpleGuardedExecModule...
✅ SimpleGuardedExecModule deployed to: 0xijkl...mnop

📊 Deployment Summary:
=====================
Network: Base Mainnet
Deployer: 0x1234...5678
SimpleTargetRegistry: 0xabcd...efgh
SimpleGuardedExecModule: 0xijkl...mnop

✅ All contracts verified successfully!
🎉 Deployment completed successfully!
```

### Successful Integration Test
```
🧪 Testing full integration flow...

🔍 Test 1: Verifying whitelist status...
✅ Whitelist verification passed

🔍 Test 2: Testing ERC20 transfer authorization...
✅ ERC20 transfer authorization working correctly

🔍 Test 3: Testing module pause functionality...
✅ Module is not paused (expected)

🔍 Test 4: Testing session key execution simulation...
✅ Session key execution would be allowed

🔍 Test 5: Testing non-whitelisted operation...
✅ Non-whitelisted operations are blocked

✅ All integration tests completed!
🎉 Your GuardedExecModule is ready for production use!
```

## 🚨 Troubleshooting

### Common Issues

1. **Insufficient ETH**
   ```
   Error: Insufficient ETH for deployment
   ```
   Solution: Add more Base ETH to your account

2. **RPC Rate Limits**
   ```
   Error: HTTP status client self (429 Too Many Requests)
   ```
   Solution: Use a premium RPC provider or wait

3. **Module Installation Failed**
   ```
   Error: Module installation failed
   ```
   Solution: Ensure Safe account has sufficient ETH and try again

4. **Session Key Generation Failed**
   ```
   Error: Session key creation failed
   ```
   Solution: Check private key format and try again

### Debug Commands

```bash
# Check contract deployment
pnpm run deploy:base

# Verify Safe account creation
pnpm run create-safe-account

# Test individual components
pnpm run test-integration
```

## 📈 Production Deployment

### Pre-deployment Checklist
- [ ] Test on Base testnet first
- [ ] Verify all environment variables
- [ ] Ensure sufficient ETH for gas
- [ ] Review whitelist configuration
- [ ] Test session key functionality

### Production Steps
1. Deploy contracts to Base mainnet
2. Create production Safe account
3. Install GuardedExecModule
4. Configure production whitelist
5. Generate production session keys
6. Set up monitoring and alerts

### Monitoring
- Monitor Safe account transactions
- Track session key usage
- Alert on unauthorized access attempts
- Monitor contract events

## 🔗 Resources

- [Rhinestone Documentation](https://docs.rhinestone.dev/build-modules/overview)
- [Safe Protocol Documentation](https://docs.safe.global/)
- [Base Network Documentation](https://docs.base.org/)
- [ERC-7579 Standard](https://eips.ethereum.org/EIPS/eip-7579)

## 📞 Support

For issues or questions:
1. Check the troubleshooting section
2. Review the integration test output
3. Verify environment configuration
4. Check Base network status

---

**🎉 Congratulations!** You now have a fully functional GuardedExecModule deployed on Base network with Safe smart account integration and session key management.
