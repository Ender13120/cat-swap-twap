// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

contract ExecuteTWAP is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11cCD98850c568eA86d964dabE7afeB085b7DFe));

    // Updated with the new TWAP order hash from RegisterTWAP simulation
    bytes32 constant ORDER_HASH =
        0xab7aee9aa446b32d689ae140977102c47b78064afd901bac400b759892c901aa;

    // User address (should be the one that created the order)
    address constant USER = 0xa11cCD98850c568eA86d964dabE7afeB085b7DFe;
    uint256 constant USER_PK =
        0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9;

    // Implementation contract address for EIP-7702 (newly deployed)
    address constant IMPLEMENTATION_ADDRESS =
        0xE92a890a2Bf4105e7240e0a6465141FA1fA7530D;

    // Integrator wallet (the one executing TWAP parts - gets tips)
    address constant INTEGRATOR = 0x666666Af7429e4B3C00B9CCAaFDC6CEda313EBe6;

    function run() external {
        vm.startBroadcast(USER_PK);

        console.log("=== EXECUTING TWAP PART ON-CHAIN ===");
        console.log("Contract Address:", address(WALLET));
        console.log("Implementation:", IMPLEMENTATION_ADDRESS);
        console.log("Order Hash:", vm.toString(ORDER_HASH));

        // Get current status
        (
            DelegatedWallet.LimitOrder memory order,
            uint256 executedParts,
            uint256 nextExecutionTime,
            bool isComplete
        ) = WALLET.getTWAPStatus(ORDER_HASH);

        console.log("\nCurrent Status:");
        console.log("- Total Parts:", order.twapParts);
        console.log("- Executed Parts:", executedParts);
        console.log("- Next Execution Time:", nextExecutionTime);
        console.log("- Current Time:", block.timestamp);
        console.log("- Is Complete:", isComplete);
        console.log("- Maker Asset:", order.makerAsset);
        console.log("- Taker Asset:", order.takerAsset);

        if (isComplete) {
            console.log("\n[INFO] TWAP already complete!");
            vm.stopBroadcast();
            return;
        }

        if (block.timestamp < nextExecutionTime) {
            console.log("\n[INFO] Too early to execute next part!");
            console.log("Wait until:", nextExecutionTime);
            console.log(
                "Time remaining:",
                nextExecutionTime - block.timestamp,
                "seconds"
            );
            vm.stopBroadcast();
            return;
        }

        // Calculate current price (simplified - in real use you'd get from oracle/DEX)
        // For demo purposes, using the original price ratio
        uint256 currentPrice = (order.takingAmount * 1e18) / order.makingAmount;

        console.log("\nExecuting part", executedParts, "of", order.twapParts);
        console.log("Current price:", currentPrice);
        console.log("Integrator:", INTEGRATOR);

        // Use EIP-7702 delegation to execute TWAP part
        console.log("\nSetting up EIP-7702 delegation...");
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        // Prepare extension data for 1inch order (can be empty for basic orders)
        bytes memory extension = "";

        console.log("\nExecuting TWAP part with on-chain registration...");

        try
            WALLET.executeTWAPPart(
                ORDER_HASH,
                executedParts, // Next part index
                currentPrice,
                INTEGRATOR,
                extension // Extension data for 1inch OrderRegistrator
            )
        returns (bytes32 oneinchOrderHash) {
            console.log(
                "\n[SUCCESS] TWAP part executed and registered on-chain!"
            );
            console.log("1inch order hash:", vm.toString(oneinchOrderHash));

            // Check if the order was registered with the OrderRegistrator
            console.log("Order registered on 1inch OrderRegistrator");

            // Get updated status
            (
                ,
                uint256 newExecutedParts,
                uint256 newNextTime,
                bool newIsComplete
            ) = WALLET.getTWAPStatus(ORDER_HASH);
            console.log("\nUpdated Status:");
            console.log("- New executed parts:", newExecutedParts);
            console.log("- Is complete:", newIsComplete);

            if (!newIsComplete) {
                console.log("- Next execution time:", newNextTime);
                console.log(
                    "- Time until next execution:",
                    newNextTime > block.timestamp
                        ? newNextTime - block.timestamp
                        : 0,
                    "seconds"
                );
                console.log(
                    "\n[INFO] Run this script again after the next execution time"
                );
            } else {
                console.log("\n[SUCCESS] TWAP execution complete!");
                console.log("All", order.twapParts, "parts have been executed");
            }
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Execution failed:", reason);

            // Provide specific guidance for common errors
            if (
                keccak256(bytes(reason)) ==
                keccak256(bytes("Order not registered"))
            ) {
                console.log(
                    "Suggestion: Make sure the TWAP order was registered first"
                );
            } else if (
                keccak256(bytes(reason)) == keccak256(bytes("Order cancelled"))
            ) {
                console.log("Suggestion: The order has been cancelled");
            } else {
                console.log("Check the order status and timing requirements");
            }
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Execution failed with low-level error");
            console.logBytes(lowLevelData);

            // Try to decode common revert reasons
            if (lowLevelData.length >= 4) {
                bytes4 selector = bytes4(lowLevelData);
                console.log("Error selector:", vm.toString(selector));

                // Check for known error selectors
                if (selector == DelegatedWallet.TWAPNotStarted.selector) {
                    console.log("Error: TWAP not started yet");
                } else if (selector == DelegatedWallet.TWAPEnded.selector) {
                    console.log("Error: TWAP has ended");
                } else if (
                    selector == DelegatedWallet.TWAPPartAlreadyExecuted.selector
                ) {
                    console.log(
                        "Error: This TWAP part has already been executed"
                    );
                } else if (
                    selector == DelegatedWallet.TWAPPartNotReady.selector
                ) {
                    console.log("Error: TWAP part not ready for execution yet");
                } else if (
                    selector == DelegatedWallet.PriceDeviationTooHigh.selector
                ) {
                    console.log("Error: Price deviation too high");
                }
            }
        }

        vm.stopBroadcast();
    }
}
