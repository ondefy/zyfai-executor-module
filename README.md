# GuardedExecModule

### Run Tests
```bash
# Test both approaches
forge test

forge test --match-path "test/*"

# Run all tests
forge test --match-path test/GuardedExecModule.t.sol -vv

# Run specific test
forge test --match-test test_MsgSenderIsSmartAccount -vv

# Gas report
forge test --match-path test/GuardedExecModule.t.sol --gas-report

# test upgradable module
forge test --match-path test/GuardedExecModuleUpgradeableTest.t.sol -vvv
```

## Deploy and Verify

```bash
# Deploy new TargetRegistry
PRIVATE_KEY=pk-add-here forge script script/1-DeployTargetRegistry.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --broadcast -vvvv

# Verify TargetRegistry
forge verify-contract <TARGET_REGISTRY_ADDRESS> src/registry/TargetRegistry.sol:TargetRegistry --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key-add-here --constructor-args 0x000000000000000000000000<OWNER_ADDRESS>

# Upgrade Module
TARGET_REGISTRY_ADDRESS=0xFEe351d2Bf326AAfF9d4621c8BB2Ab7b2fe8780c forge script script/2-UpgradeAndUpdateModule.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --private-key pk --broadcast -vvvv

# Verify New Impl of Module
forge verify-contract 0xaE5eA5a3F4E3cB6B8D3e11aC4f50F484EC8f4cD8 src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key

# Proxy Verify
forge verify-contract 0x7B3072f06105c08de4997bdC74C7095327fD475c lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --constructor-args 0x000000000000000000000000079c22bbd7b5b91bde24687036d3d3ee2b6c634c00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000044485cc955000000000000000000000000a0bee327a95f786f5097028ee250c4834dfeb629000000000000000000000000d61c43c089852e0ab68b967dd1ede03a18e5222300000000000000000000000000000000000000000000000000000000 --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key etherscan-key
```

## Quick Deploy

```solidity
// 1. Deploy registry
TargetRegistry registry = new TargetRegistry(owner);

// 2. Deploy module
GuardedExecModule module = new GuardedExecModule(address(registry));

// 3. Install on smart account
smartAccount.installModule(MODULE_TYPE_EXECUTOR, module, "");
```
