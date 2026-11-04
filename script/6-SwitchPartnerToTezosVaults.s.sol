// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { TargetRegistry } from "../src/registry/TargetRegistry.sol";

/**
 * @title Switch Partner To Tezos Vaults
 * @notice Replaces the IPOR "Nvidia Carry Trade" pairs written by
 *         script/5-WhitelistPartnerNvda.s.sol with the four Tezos-owned IPOR vaults, on a
 *         partner TargetRegistry. Run BEFORE script/4-TransferPartnerOwnership.s.sol
 *         (onlyOwner, and the registry must not be paused).
 * @dev Two differences from the public vault this replaces:
 *
 *      1. Deposits are gated behind IPOR WHITELIST_ROLE (800) on each vault's AccessManager.
 *         The caller the vault sees is the partner Adapter, not the account, so the partner's
 *         atomist must grant role 800 to PARTNER_ADAPTER on all four AccessManagers. Without
 *         it depositVaultForSelf reverts AccessManagedUnauthorized.
 *      2. transfer/transferFrom on the shares sit behind TECH_VAULT_TRANSFER_SHARES_ROLE (7),
 *         held only by the FeeManager. redeemVaultForSelf moves shares to the Adapter first,
 *         so it can never succeed here and is deliberately NOT whitelisted. Exits are
 *         WithdrawManager.requestShares -> alpha releaseFunds -> Adapter.redeemFromRequestForSelf,
 *         which burns the account's own shares.
 *
 *      The partner Adapter must also allow the four vaults (defi-adapter ConfigureVault) and
 *      delist the public one. No ERC20 recipient entry is needed: transfers to the Safe's own
 *      owners are authorized natively by the registry.
 *
 *      Run with:
 *      PARTNER_TARGET_REGISTRY=0x... \
 *      PARTNER_ADAPTER=0x... \
 *      forge script script/6-SwitchPartnerToTezosVaults.s.sol --rpc-url $RPC_URL \
 *        --private-key $PRIVATE_KEY --broadcast -vvvv
 */
contract SwitchPartnerToTezosVaults is Script {
    // Pairs written by script 5, around IPOR's public Nvidia Carry Trade.
    address internal constant PUBLIC_NVDA_VAULT = 0xFb132f4C6d9DCF4f80483Ea7D96C5A5dccfcFE83;
    address internal constant PUBLIC_NVDA_WITHDRAW_MANAGER = 0x7a4AaC4137d96EE075fC7862531e54a687f9A2b7;

    // Underlying assets of the four Tezos vaults.
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant NVDAC = 0xb20000000000000000000078ee7ce2fE4908108C;
    address internal constant GOOGLC = 0xb2000000000000000000002D0BA3164cc74f58B7;
    address internal constant METAC = 0xb2000000000000000000008bC8786B856E61707C;

    // Tezos-owned vaults, with the WithdrawManager read from each vault's ERC-7201
    // io.ipor.WithdrawManager slot and cross-checked with getPlasmaVaultAddress().
    address internal constant USDC_VAULT = 0x585AA9EB2C8D51Ab5f436b27B11bB23350570B3F;
    address internal constant USDC_WITHDRAW_MANAGER = 0xF7d5126282A5A7a93A99AAB382C1B901792D3768;
    address internal constant NVDA_VAULT = 0xDE09e16675B667B6aBB6d7910d6e009f630BcB96;
    address internal constant NVDA_WITHDRAW_MANAGER = 0x26BaD8dCA2E96a9b6bb31A95c1187DB43FD55823;
    address internal constant GOOGL_VAULT = 0x61AEF0Bb9AD09C0d736b047F2b7Bc69E566467eA;
    address internal constant GOOGL_WITHDRAW_MANAGER = 0xf3c4B07010FD41F00614E3740698b92063239279;
    address internal constant META_VAULT = 0x5130ccfAe447b1Bd512468B5a850B07d63a31163;
    address internal constant META_WITHDRAW_MANAGER = 0xC71Edf0b2B4094A64fD44c6Dc0EecEA43F8e8803;

    bytes4 internal constant APPROVE = 0x095ea7b3;
    bytes4 internal constant TRANSFER = 0xa9059cbb;
    bytes4 internal constant REQUEST_SHARES = 0xfc415e9c;
    bytes4 internal constant DEPOSIT_VAULT_FOR_SELF = 0x1c78885e;
    bytes4 internal constant REDEEM_VAULT_FOR_SELF = 0xd9baa570;
    bytes4 internal constant REDEEM_FROM_REQUEST_FOR_SELF = 0xaaa05e2a;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        TargetRegistry registry = TargetRegistry(vm.envAddress("PARTNER_TARGET_REGISTRY"));
        address adapter = vm.envAddress("PARTNER_ADAPTER");

        require(registry.owner() == deployer, "Deployer does not own the registry");
        require(adapter.code.length > 0, "PARTNER_ADAPTER has no code");

        (address[] memory stale, bytes4[] memory staleSelectors) = _stalePairs(adapter);
        (address[] memory targets, bytes4[] memory selectors) = _tezosPairs(adapter);

        // addToWhitelist and removeFromWhitelist both revert on a redundant operation, and
        // the two sets overlap (NVDAc approve/transfer and depositVaultForSelf already exist
        // from script 5). Filtering on current state also makes this script re-runnable.
        (address[] memory toRemove, bytes4[] memory removeSelectors) =
            _filter(registry, stale, staleSelectors, true);
        (address[] memory toAdd, bytes4[] memory addSelectors) = _filter(registry, targets, selectors, false);

        console.log("=== Switching partner registry to the Tezos vaults ===");
        console.log("Registry:", address(registry));
        console.log("Adapter:", adapter);

        vm.startBroadcast(deployerPrivateKey);
        if (toRemove.length > 0) registry.removeFromWhitelist(toRemove, removeSelectors);
        if (toAdd.length > 0) registry.addToWhitelist(toAdd, addSelectors);
        vm.stopBroadcast();

        for (uint256 i = 0; i < stale.length; i++) {
            require(!registry.whitelist(stale[i], staleSelectors[i]), "Stale pair still whitelisted");
        }
        for (uint256 i = 0; i < targets.length; i++) {
            require(registry.whitelist(targets[i], selectors[i]), "Pair not whitelisted");
        }

        // The whole point of the switch: the public vault must be unreachable, and the
        // instant exit must stay unreachable on vaults whose shares cannot be transferred.
        require(!registry.whitelist(PUBLIC_NVDA_VAULT, APPROVE), "Public vault still reachable");
        require(!registry.whitelist(adapter, REDEEM_VAULT_FOR_SELF), "Instant redeem still whitelisted");

        console.log("Removed pairs:", toRemove.length);
        console.log("Added pairs:", toAdd.length);
        console.log("Whitelisted pairs:", targets.length);
    }

    /// @notice Keep the pairs whose current whitelist state equals `whitelisted`.
    function _filter(
        TargetRegistry registry,
        address[] memory targets,
        bytes4[] memory selectors,
        bool whitelisted
    )
        internal
        view
        returns (address[] memory keptTargets, bytes4[] memory keptSelectors)
    {
        uint256 count;
        for (uint256 i = 0; i < targets.length; i++) {
            if (registry.whitelist(targets[i], selectors[i]) == whitelisted) count++;
        }

        keptTargets = new address[](count);
        keptSelectors = new bytes4[](count);

        uint256 j;
        for (uint256 i = 0; i < targets.length; i++) {
            if (registry.whitelist(targets[i], selectors[i]) == whitelisted) {
                keptTargets[j] = targets[i];
                keptSelectors[j] = selectors[i];
                j++;
            }
        }
    }

    /// @notice The pairs script 5 wrote. NVDAc approve/transfer stay: the Tezos NVDA vault reuses them.
    function _stalePairs(address adapter)
        internal
        pure
        returns (address[] memory targets, bytes4[] memory selectors)
    {
        targets = new address[](3);
        selectors = new bytes4[](3);
        (targets[0], selectors[0]) = (PUBLIC_NVDA_VAULT, APPROVE);
        (targets[1], selectors[1]) = (PUBLIC_NVDA_WITHDRAW_MANAGER, REQUEST_SHARES);
        (targets[2], selectors[2]) = (adapter, REDEEM_VAULT_FOR_SELF);
    }

    /// @notice approve + transfer per asset, approve per vault, requestShares per
    ///         WithdrawManager, and the two Adapter entrypoints the async cycle needs.
    function _tezosPairs(address adapter)
        internal
        pure
        returns (address[] memory targets, bytes4[] memory selectors)
    {
        targets = new address[](18);
        selectors = new bytes4[](18);

        (targets[0], selectors[0]) = (USDC, APPROVE);
        (targets[1], selectors[1]) = (USDC, TRANSFER);
        (targets[2], selectors[2]) = (NVDAC, APPROVE);
        (targets[3], selectors[3]) = (NVDAC, TRANSFER);
        (targets[4], selectors[4]) = (GOOGLC, APPROVE);
        (targets[5], selectors[5]) = (GOOGLC, TRANSFER);
        (targets[6], selectors[6]) = (METAC, APPROVE);
        (targets[7], selectors[7]) = (METAC, TRANSFER);

        (targets[8], selectors[8]) = (USDC_VAULT, APPROVE);
        (targets[9], selectors[9]) = (NVDA_VAULT, APPROVE);
        (targets[10], selectors[10]) = (GOOGL_VAULT, APPROVE);
        (targets[11], selectors[11]) = (META_VAULT, APPROVE);

        (targets[12], selectors[12]) = (USDC_WITHDRAW_MANAGER, REQUEST_SHARES);
        (targets[13], selectors[13]) = (NVDA_WITHDRAW_MANAGER, REQUEST_SHARES);
        (targets[14], selectors[14]) = (GOOGL_WITHDRAW_MANAGER, REQUEST_SHARES);
        (targets[15], selectors[15]) = (META_WITHDRAW_MANAGER, REQUEST_SHARES);

        (targets[16], selectors[16]) = (adapter, DEPOSIT_VAULT_FOR_SELF);
        (targets[17], selectors[17]) = (adapter, REDEEM_FROM_REQUEST_FOR_SELF);
    }
}
