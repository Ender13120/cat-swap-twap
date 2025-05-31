// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/Firstdraft.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the DelegatedWallet contract
        DelegatedWallet wallet = new DelegatedWallet(
            0x111111125421cA6dc452d289314280a0f8842A65
        );

        console.log("DelegatedWallet deployed to:", address(wallet));

        vm.stopBroadcast();
    }
}
