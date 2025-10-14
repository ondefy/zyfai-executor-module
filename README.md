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
