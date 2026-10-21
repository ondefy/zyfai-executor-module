# Partner-owned GuardedExecModule + TargetRegistry (Base)

Runbook for handing a partner a **dedicated** GuardedExecModule proxy + TargetRegistry that they
own on-chain. Their smart wallets install this module instead of the shared one
(`0xF659d30D4EB88B06A909F20839D8959Bd77d8790`); the shared Adapter
(`0xaffD3c3cD06cf499deddf78b26868018A93f2C31`) stays whitelisted in their registry so our session
keys keep executing rebalances.

## Ownership model

- **TargetRegistry** (Ownable2Step): the partner is the only authority over the whitelist. No
  backend in the loop — they build and sign `addToWhitelist` / `removeFromWhitelist` /
  `addAllowedERC20TokenRecipient` transactions themselves.
- **GuardedExecModule proxy** (UUPS + Ownable2Step): the owner can upgrade the implementation,
  which is de-facto custody over every wallet that installs the module. Acceptable by design here
  because **only the partner's own wallets install it** — no existing wallet is affected.
  Recommend the partner use a multisig as owner.
- If the partner removes the Adapter from their whitelist, execution reverts — fail safe, no fund
  loss.

## Procedure

All commands run from this repo. `PRIVATE_KEY` is our deployer key; never echo or commit it.

### 1. Deploy registry + module (deployer as temporary owner)

```bash
forge script script/3-DeployPartnerInstance.s.sol \
  --rpc-url $BASE_RPC_URL --broadcast --verify
```

Deploys `TargetRegistry(deployer)`, the `GuardedExecModuleUpgradeable` implementation, and an
ERC1967 proxy initialized with `(registry, deployer)`. Record the **registry** and **module proxy**
addresses from the logs.

### 2. Clone the Base whitelist (while we still own the registry)

The Base whitelist scripts read the target registry from `BASE_TARGET_REGISTRY_ADDRESS`:

```bash
BASE_TARGET_REGISTRY_ADDRESS=<partner registry> \
  npx ts-node hardhat/scripts/addWhitelist/4.0-base-whitelist-registry.ts

BASE_TARGET_REGISTRY_ADDRESS=<partner registry> \
  npx ts-node hardhat/scripts/addRecipientForTransfer/6-add-erc20-token-recipient-base.ts
```

This copies the Adapter selectors, ERC20 approve spenders, and allowed ERC20 recipients from
`hardhat/protocolData/basedata.ts`.

### 3. Transfer ownership of all four contracts

The partner must end up owning the **registry, module proxy, adapter proxy AND the adapter's
beacon** — the beacon owner controls the adapter implementation, so leaving it behind would
leave Zyfai with de-facto control over the adapter.

```bash
PARTNER_OWNER=<partner multisig> \
PARTNER_TARGET_REGISTRY=<partner registry> \
PARTNER_GUARDED_EXEC_MODULE=<partner module proxy> \
PARTNER_ADAPTER=<partner adapter proxy> \
PARTNER_ADAPTER_BEACON=<partner adapter beacon> \
forge script script/4-TransferPartnerOwnership.s.sol \
  --rpc-url $BASE_RPC_URL --broadcast
```

Registry, module and adapter are **Ownable2Step**: the transfer only sets `pendingOwner` and
the partner must call `acceptOwnership()` on all three from their owner wallet. The **beacon is
a plain Ownable**: its transfer is one-step and effective immediately — triple-check
`PARTNER_OWNER` before broadcasting. Verify `owner()` on all four afterwards (BaseScan), plus
`pendingOwner() == 0` on the three 2-step contracts once accepted.

### 4. Wire into zyfai-api

Add the partner's **sign-in EOA** (the wallet they use for SIWE) to `PARTNER_EXECUTOR_CONFIG` in
`zyfai-api/src/constants/partner-executor.constants.ts` with the deployed module + registry
addresses and `chains: [Base]`, then deploy the API.

On their next SIWE sign-in the user row is stamped (`executor_module_address`, `predeployed =
false`, chains pinned to Base) and `safe-deploy` installs **their** module on their smart account.

### 5. Post-onboarding checks

- Verify both contracts on BaseScan and record the addresses in the wiki (`Integrations_2.md`
  style ops note): registry, module proxy, implementation, owner.
- After the partner's first sign-in, check `user.executor_module_address` is set — an address typo
  in the config map silently onboards them on the shared module.

## Deployed instances

| Partner | Registry | Module proxy | Owner | Date |
|---|---|---|---|---|
| _(none yet)_ | | | | |
