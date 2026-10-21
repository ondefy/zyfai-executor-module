// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { TargetRegistry } from "../src/registry/TargetRegistry.sol";

/**
 * @title Whitelist Partner NVDA
 * @notice Whitelists exactly the IPOR "Nvidia Carry Trade" (NVDAc) pairs on a partner
 *         TargetRegistry — the same pairs the shared prod registry
 *         (0xd5C2dFD6d34c2bEA1dbec14DE4780d4A9D45ea17) holds for this vault, pointed at the
 *         partner Adapter. Run BEFORE script/4-TransferPartnerOwnership.s.sol (onlyOwner).
 * @dev The vault is async: exits go WithdrawManager.requestShares -> alpha releaseFunds ->
 *      Adapter.redeemFromRequestForSelf. The partner Adapter must also allow the vault
 *      (defi-adapter ConfigureVault). No ERC20 recipient entry is needed: NVDAc transfers to
 *      the Safe's own owners are authorized natively by the registry.
 *
 *      Run with:
 *      PARTNER_TARGET_REGISTRY=0x... \
 *      PARTNER_ADAPTER=0x... \
 *      forge script script/5-WhitelistPartnerNvda.s.sol --rpc-url $RPC_URL \
 *        --private-key $PRIVATE_KEY --broadcast -vvvv
 */
contract WhitelistPartnerNvda is Script {
    address internal constant NVDAC = 0xb20000000000000000000078ee7ce2fE4908108C;
    address internal constant NVDA_VAULT = 0xFb132f4C6d9DCF4f80483Ea7D96C5A5dccfcFE83;
    address internal constant NVDA_WITHDRAW_MANAGER = 0x7a4AaC4137d96EE075fC7862531e54a687f9A2b7;

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

        address[] memory targets = new address[](7);
        bytes4[] memory selectors = new bytes4[](7);
        (targets[0], selectors[0]) = (NVDAC, APPROVE);
        (targets[1], selectors[1]) = (NVDAC, TRANSFER);
        (targets[2], selectors[2]) = (NVDA_VAULT, APPROVE);
        (targets[3], selectors[3]) = (NVDA_WITHDRAW_MANAGER, REQUEST_SHARES);
        (targets[4], selectors[4]) = (adapter, DEPOSIT_VAULT_FOR_SELF);
        (targets[5], selectors[5]) = (adapter, REDEEM_VAULT_FOR_SELF);
        (targets[6], selectors[6]) = (adapter, REDEEM_FROM_REQUEST_FOR_SELF);

        console.log("=== Whitelisting NVDA pairs ===");
        console.log("Registry:", address(registry));
        console.log("Adapter:", adapter);

        vm.startBroadcast(deployerPrivateKey);
        registry.addToWhitelist(targets, selectors);
        vm.stopBroadcast();

        for (uint256 i = 0; i < targets.length; i++) {
            require(registry.whitelist(targets[i], selectors[i]), "Pair not whitelisted");
        }
        console.log("7 pairs whitelisted");
    }
}
