// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract SetupDelegation is Script {
    // User wallet that needs delegation
    address constant USER = 0xa11ceB73aB7888736F264A3502933178f0a18553;

    // Implementation contract address for EIP-7702
    address constant IMPLEMENTATION_ADDRESS =
        0x6B90FAF6d634EDE2E56c024A9b852A9607a5c7bf;

    function run() external {
        // Load USER_PK from environment
        uint256 USER_PK = vm.envUint("USER_PK");

        console.log("=== SETTING UP EIP-7702 DELEGATION ===");
        console.log("User Address:", USER);
        console.log("Implementation Address:", IMPLEMENTATION_ADDRESS);

        // Start broadcast with user's key (the user must sign the delegation)
        vm.startBroadcast(USER_PK);

        // Attach delegation - this sets up EIP-7702 for the user's EOA
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        vm.stopBroadcast();

        console.log("\n[SUCCESS] EIP-7702 delegation set up!");
        console.log(
            "The address",
            USER,
            "now delegates to",
            IMPLEMENTATION_ADDRESS
        );
        console.log("\nYou can now run batch swap operations on this address.");
    }
}
