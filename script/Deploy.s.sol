// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 1inch Limit Order Protocol on Ethereum mainnet
        address limitOrderProtocol = 0x111111125421cA6dc452d289314280a0f8842A65;

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying DelegatedWallet...");
        console.log("1inch Protocol:", limitOrderProtocol);

        DelegatedWallet wallet = new DelegatedWallet(limitOrderProtocol);

        console.log("DelegatedWallet deployed at:", address(wallet));

        vm.stopBroadcast();
    }
}
