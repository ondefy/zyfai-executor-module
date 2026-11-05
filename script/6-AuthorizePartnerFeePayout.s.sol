// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { TargetRegistry } from "../src/registry/TargetRegistry.sol";

/**
 * @title Authorize partner fee payout
 * @notice Authorizes the Owney payout as an ERC20 transfer recipient on one token.
 *         `partner_fee_payout_address` is global, so run this for every fee token on
 *         every chain that collects performance fees (mainnet, Base, Arbitrum, Plasma,
 *         Sonic) before that column is set. A missing recipient reverts the userop.
 * @dev Does not broadcast unless forge is invoked with `--broadcast`.
 *
 *      TARGET_REGISTRY=0x... TOKEN=0x... \
 *      forge script script/6-AuthorizePartnerFeePayout.s.sol \
 *        --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract AuthorizePartnerFeePayout is Script {
    address internal constant OWNEY_FEE_PAYOUT = 0x5d382abA27cd6a828F29Db4fac7aEf1CB7E701e2;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        TargetRegistry registry = TargetRegistry(vm.envAddress("TARGET_REGISTRY"));
        address token = vm.envAddress("TOKEN");

        if (registry.allowedERC20TokenRecipients(token, OWNEY_FEE_PAYOUT)) {
            console.log("already authorized", OWNEY_FEE_PAYOUT);
            return;
        }

        address[] memory recipients = new address[](1);
        recipients[0] = OWNEY_FEE_PAYOUT;

        console.log("Registry:", address(registry));
        console.log("Token:", token);
        console.log("Payout:", OWNEY_FEE_PAYOUT);

        vm.startBroadcast(deployerPrivateKey);
        registry.addAllowedERC20TokenRecipient(token, recipients);
        vm.stopBroadcast();
    }
}
