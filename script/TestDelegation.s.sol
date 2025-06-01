// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

contract TestDelegation is Script {
    address constant USER = 0xa11ceB73aB7888736F264A3502933178f0a18553;
    address constant IMPLEMENTATION =
        0x6B90FAF6d634EDE2E56c024A9b852A9607a5c7bf;

    function run() external {
        uint256 USER_PK = vm.envUint("USER_PK");

        console.log("=== TESTING EIP-7702 DELEGATION ===");
        console.log("User:", USER);
        console.log("Implementation:", IMPLEMENTATION);

        // Check if address has code (delegation set up)
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(USER)
        }
        console.log("Current code size at user address:", codeSize);

        if (codeSize == 0) {
            console.log(
                "\n[INFO] No delegation set up yet. Setting it up now..."
            );

            // Set up delegation as the user
            vm.startBroadcast(USER_PK);

            // This should add the delegation
            vm.signAndAttachDelegation(IMPLEMENTATION, USER_PK);

            // Try a simple call to test
            (bool success, ) = USER.call(abi.encodeWithSignature("nonce()"));

            if (success) {
                console.log("[SUCCESS] Delegation set up and working!");
            } else {
                console.log(
                    "[WARNING] Delegation might not be working properly"
                );
            }

            vm.stopBroadcast();
        } else {
            console.log("\n[INFO] Delegation appears to be already set up");

            // Test if it's working
            vm.startBroadcast(USER_PK);
            DelegatedWallet wallet = DelegatedWallet(payable(USER));
            uint256 nonce = wallet.nonce();
            console.log("Wallet nonce:", nonce);
            vm.stopBroadcast();
        }
    }
}
