# CREATE3 Deployment Guide

This guide explains how to deploy `GuardedExecModuleUpgradeable` using CREATE3, which allows you to:

- ✅ **Same addresses on every chain** (deterministic deployment)
- ✅ **Different init params per chain** (e.g., different `registry` address)
- ✅ **Single transaction deployment** (init data in constructor, no front-running risk)

## How CREATE3 Works

CREATE3 is a pattern that makes contract addresses depend **only on the factory address and salt**, not on the creation bytecode or init data.

1. **Factory Deployment**: The `Create3Factory` is deployed deterministically via CREATE2 (using Nick's factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`)
2. **Intermediate Deployer**: For each deployment, CREATE2 deploys an ephemeral `Create3Deployer` contract
3. **Final Deployment**: The deployer uses CREATE (nonce=1) to deploy your contract
4. **Result**: The final address depends only on `(factory_address, salt)`, not on `initCode`

### Key Advantage

With CREATE3, you can include different initialization data per chain (e.g., different `registry` addresses) while still getting the **same proxy address on all chains**.

## Files

- `script/Create3Factory.sol` - The CREATE3 factory contract
- `script/Create3Deployer.sol` - Ephemeral deployer used internally
- `script/DeployWithCREATE3.s.sol` - Deployment script

## Usage

### 1. Set Environment Variables

```bash
export PRIVATE_KEY=0xYourPrivateKey
export TARGET_REGISTRY_ADDRESS=0xYourRegistryAddress  # Can differ per chain!
```

### 2. Deploy on Base

```bash
forge script script/DeployWithCREATE3.s.sol:DeployWithCREATE3 \
  --rpc-url $BASE_RPC \
  --broadcast \
  -vvvv
```

### 3. Deploy on Arbitrum (or any other chain)

```bash
# Use different registry if needed
export TARGET_REGISTRY_ADDRESS=0xYourRegistryOnArbitrum

forge script script/DeployWithCREATE3.s.sol:DeployWithCREATE3 \
  --rpc-url $ARB_RPC \
  --broadcast \
  -vvvv
```

**Note**: Even with different `TARGET_REGISTRY_ADDRESS` values, you'll get the **same proxy address** on all chains!

## What Gets Deployed

1. **Create3Factory** - Deployed once via CREATE2 (same address on all chains)
2. **Implementation** - Deployed via CREATE3 (same address on all chains)
3. **Proxy** - Deployed via CREATE3 with init data in constructor (same address on all chains, different init params per chain)

## Addresses

The script uses fixed salts:
- `FACTORY_SALT`: `keccak256("zyfai-create3-factory-v1")`
- `IMPL_SALT`: `keccak256("GuardedExecModuleUpgradeable-impl-v1")`
- `PROXY_SALT`: `keccak256("GuardedExecModuleUpgradeable-proxy-v1")`

These ensure deterministic addresses across all chains.

## Post-Deployment Verification

### Check UUPS Implementation Slot

```bash
cast storage $PROXY \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  --rpc-url $RPC
```

Should equal the implementation address.

### Check Admin Slot (Must Be Zero for UUPS)

```bash
cast storage $PROXY \
  0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 \
  --rpc-url $RPC
```

Should be `0x0000000000000000000000000000000000000000000000000000000000000000`.

### Check Owner

```bash
cast call $PROXY "owner()" --rpc-url $RPC
```

Should return the owner address.

### Check Registry

```bash
cast call $PROXY "registry()" --rpc-url $RPC
```

Should return the registry address (may differ per chain).

## Comparison with CREATE2

| Feature | CREATE2 | CREATE3 |
|---------|---------|---------|
| Deterministic addresses | ✅ | ✅ |
| Same address across chains | ✅ (if init data same) | ✅ (even if init data differs) |
| Init data in constructor | ❌ (breaks determinism) | ✅ (safe) |
| Front-running protection | ❌ (needs separate init tx) | ✅ (atomic deployment) |
| Complexity | Simple | More complex |

## When to Use CREATE3

Use CREATE3 when:
- You need **different initialization parameters per chain** (e.g., different registry addresses)
- You want **atomic deployment + initialization** (prevents front-running)
- You still need **same addresses on all chains**

Use CREATE2 when:
- Your initialization parameters are **the same on all chains**
- You want a **simpler deployment process**

## Troubleshooting

### Factory Already Deployed

If the factory is already deployed, the script will detect it and reuse it. No action needed.

### Contract Already Deployed

If a contract is already deployed at the predicted address, the script will skip deployment. To redeploy, you'll need to:
1. Use a different salt, OR
2. Deploy to a different factory address

### Different Addresses Across Chains

If you're getting different addresses:
1. Check that you're using the same salts
2. Verify the factory address is the same on all chains
3. Ensure compiler settings are identical (`foundry.toml`)

## Foundry Configuration

Ensure your `foundry.toml` has deterministic build settings:

```toml
[profile.default]
solc = "0.8.23"        # pin compiler version
evm_version = "cancun" # pin EVM version
bytecode_hash = "none"
cbor_metadata = false
always_use_create_2_factory = true
```

## Security Notes

1. **UUPS Pattern**: The proxy uses UUPS (no admin slot), so upgrades are controlled by the `owner` via `_authorizeUpgrade`
2. **Initialization**: Initialization happens atomically during deployment, preventing front-running
3. **Deterministic**: Same addresses across chains make it easier to manage multi-chain deployments
4. **Registry**: Each chain can have its own registry address while maintaining the same proxy address

## References

- [Nick's CREATE2 Factory](https://github.com/Arachnid/deterministic-deployment-proxy)
- [CREATE3 Pattern](https://github.com/0xsequence/create3)
- [OpenZeppelin UUPS Proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)

