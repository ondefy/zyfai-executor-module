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
# Deploy Proxy and Implementation
PRIVATE_KEY=pk-add--here forge script script/DeployUpgradeableSimple.s.sol --rpc-url https://base-mainnet.g.alchemy.com/v2/key --broadcast -vvvv


# Implementaion verify
forge verify-contract 0x079c22bBD7B5B91BDe24687036D3d3EE2b6C634C src/module/GuardedExecModuleUpgradeable.sol:GuardedExecModuleUpgradeable --rpc-url https://base-mainnet.g.alchemy.com/v2/key --chain-id 8453 --compiler-version 0.8.30 --etherscan-api-key 6MM2YK266Y6XUE337CPJFGI3RPHFQK9RKS 

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
