# Foundry Deployment Guide

This guide shows how to deploy the GuardedExecModule and TargetRegistry contracts to Base network using Foundry.

## Prerequisites

1. **Foundry installed**: `curl -L https://foundry.paradigm.xyz | bash`
2. **Base RPC URL**: Get from [Alchemy](https://www.alchemy.com/) or [Infura](https://infura.io/)
3. **Private Key**: EOA with Base ETH for gas fees
4. **Etherscan API Key**: For contract verification (optional)

## Setup

1. **Copy environment file**:
   ```bash
   cp env.example .env
   ```

2. **Edit `.env` with your values**:
   ```bash
   NETWORK=base
   RPC_URL=https://mainnet.base.org
   PRIVATE_KEY=0x1234567890abcdef...
   ETHERSCAN_API_KEY=your_api_key_here
   ```

## Deployment Steps

### Step 1: Deploy Contracts
```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

This will:
- Deploy `TargetRegistry` with you as owner
- Deploy `GuardedExecModule` with registry reference
- Save addresses to `deployments.txt`
- Verify contracts on BaseScan

### Step 2: Setup Whitelist (Schedule Operations)
```bash
forge script script/SetupWhitelist.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

This schedules whitelist additions for:
- **USDC**: transfer, transferFrom, approve
- **WETH**: deposit, withdraw, transfer  
- **DAI**: transfer, transferFrom, approve

### Step 3: Wait for Timelock (1 day)
The whitelist operations are scheduled but not active yet. Wait 24 hours or use the fast-forward script.

### Step 4: Execute Whitelist (After Timelock)
```bash
forge script script/ExecuteWhitelist.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

This activates all scheduled whitelist operations.

### Step 5: Setup ERC20 Restrictions
```bash
forge script script/SetupERC20Restrictions.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

This enables USDC transfer restrictions (only to smart wallet or owners).

### Step 6: Test Deployment
```bash
forge script script/TestDeployment.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

This verifies all contracts are working correctly.

## Contract Addresses

After deployment, you'll get addresses like:
```
TARGET_REGISTRY=0x1234567890abcdef...
GUARDED_EXEC_MODULE=0xabcdef1234567890...
DEPLOYER=0x9876543210fedcba...
```

## Integration with TypeScript

Once you have the contract addresses, update your integration tests:

1. **Update `integration-tests/env.base`**:
   ```bash
   TARGET_REGISTRY=0x1234567890abcdef...
   GUARDED_EXEC_MODULE=0xabcdef1234567890...
   ```

2. **Run integration tests**:
   ```bash
   cd integration-tests
   pnpm run full-setup
   ```

## Security Notes

- **Private Key**: Never commit your `.env` file
- **Timelock**: 24-hour delay prevents immediate changes
- **Owner Controls**: Only you can modify whitelist and restrictions
- **Pause Function**: Module can be paused in emergencies

## Troubleshooting

- **Gas Issues**: Increase gas limit with `--gas-limit 1000000`
- **Verification Fails**: Check Etherscan API key and network
- **Timelock Issues**: Ensure you wait 24 hours between schedule and execute
- **Permission Errors**: Verify you're using the correct private key

## Next Steps

After successful deployment:
1. Test with integration scripts
2. Create Safe smart account
3. Install module on Safe
4. Generate session keys
5. Test end-to-end flow
