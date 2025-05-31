// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract ExecuteBatchParts is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11cCD98850c568eA86d964dabE7afeB085b7DFe));

    // Sponsor credentials (who pays gas and executes)
    address constant SPONSOR = 0x666666Af7429e4B3C00B9CCAaFDC6CEda313EBe6;
    uint256 constant SPONSOR_PK =
        0x6b1daa76b1f3e5b5f5b9de956e093f8ab87c1f5df7ca0c8c8a3c72c07ca44a58;

    // Implementation contract address for EIP-7702
    address constant IMPLEMENTATION_ADDRESS =
        0x6B90FAF6d634EDE2E56c024A9b852A9607a5c7bf;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426;

    // 1inch Router on Optimism (v5)
    address constant ONEINCH_ROUTER =
        0x111111125421cA6dc452d289314280a0f8842A65;

    // The registered order hash from previous script
    bytes32 constant ORDER_HASH =
        0xf70c07a66a98c8eb87fd2c72d4b2241e60315a22e16c17469f958c45e72118b7;

    function run() external {
        vm.startBroadcast(SPONSOR_PK);

        console.log("=== EXECUTING BATCH SWAP PARTS ===");
        console.log("Wallet Address:", address(WALLET));
        console.log("Executor (Sponsor):", SPONSOR);
        console.log("Order Hash:", vm.toString(ORDER_HASH));

        // Check initial status
        (
            DelegatedWallet.BatchSwapOrder memory order,
            uint256 executedParts,
            uint256 nextExecutionTime,
            bool isComplete,
            bool isCancelled
        ) = WALLET.getBatchSwapStatus(ORDER_HASH);

        console.log("\nInitial Batch Order Status:");
        console.log("- Executed Parts:", executedParts, "/", order.batchParts);
        console.log("- Is Complete:", isComplete);
        console.log("- Is Cancelled:", isCancelled);

        if (isComplete) {
            console.log("\n[INFO] Batch order already complete!");
            vm.stopBroadcast();
            return;
        }

        if (isCancelled) {
            console.log("\n[ERROR] Batch order has been cancelled!");
            vm.stopBroadcast();
            return;
        }

        // Check balances
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(WALLET));
        uint256 oneinchBalanceBefore = IERC20(ONEINCH).balanceOf(
            address(WALLET)
        );

        console.log("\nInitial Balances:");
        console.log("- USDC:", usdcBalanceBefore);
        console.log("- 1INCH:", oneinchBalanceBefore);

        // Execute remaining parts
        uint256 partsToExecute = order.batchParts - executedParts;
        console.log("\nExecuting", partsToExecute, "remaining parts...");

        for (uint256 i = executedParts; i < order.batchParts; i++) {
            console.log("\n=== EXECUTING PART", i + 1, "===");

            // Check if we need to wait
            if (block.timestamp < nextExecutionTime && i > 0) {
                console.log("- Current time:", block.timestamp);
                console.log("- Next execution time:", nextExecutionTime);
                console.log(
                    "- Need to wait",
                    nextExecutionTime - block.timestamp,
                    "seconds"
                );
                // In real execution, we'd need to wait. For testing, we can use vm.warp
                vm.warp(nextExecutionTime + 1);
                console.log("- Warped to:", block.timestamp);
            }

            // Fetch fresh 1inch swap data
            console.log("- Fetching fresh 1inch swap data...");
            string[] memory inputs = new string[](3);
            inputs[0] = "node";
            inputs[1] = "fetchBatch1inch.js";
            inputs[2] = "--ffi";

            bytes memory res = vm.ffi(inputs);
            string memory output = string(res);

            // Parse the output
            bytes memory swapData;
            uint256 expectedAmount;

            bytes memory outputBytes = bytes(output);
            uint256 pipeIndex = 0;
            for (uint256 j = 0; j < outputBytes.length; j++) {
                if (outputBytes[j] == "|") {
                    pipeIndex = j;
                    break;
                }
            }

            if (pipeIndex == 0 || bytes(output).length == 0) {
                console.log("- [ERROR] Failed to fetch 1inch data");
                continue;
            }

            // Extract hex data and expected amount
            bytes memory hexBytes = new bytes(pipeIndex);
            for (uint256 j = 0; j < pipeIndex; j++) {
                hexBytes[j] = outputBytes[j];
            }
            swapData = vm.parseBytes(string(hexBytes));

            bytes memory amountBytes = new bytes(
                outputBytes.length - pipeIndex - 1
            );
            for (uint256 j = pipeIndex + 1; j < outputBytes.length; j++) {
                amountBytes[j - pipeIndex - 1] = outputBytes[j];
            }
            expectedAmount = vm.parseUint(string(amountBytes));

            console.log("- Expected 1INCH output:", expectedAmount);

            // Create the swap call
            DelegatedWallet.Call memory swapCall = DelegatedWallet.Call({
                to: ONEINCH_ROUTER,
                value: 0,
                data: swapData
            });

            // Calculate current price
            uint256 currentPrice = expectedAmount > 0
                ? (50000 * 1e18) / expectedAmount // 0.05 USDC per part
                : 3000 * 1e18;

            console.log("- Executing batch part", i, "...");

            try
                WALLET.executeBatchSwapPart(ORDER_HASH, swapCall, currentPrice)
            returns (bytes memory result) {
                console.log("- [SUCCESS] Part", i + 1, "executed!");

                // Update next execution time for next iteration
                (, , nextExecutionTime, , ) = WALLET.getBatchSwapStatus(
                    ORDER_HASH
                );
            } catch Error(string memory reason) {
                console.log("- [ERROR] Part execution failed:", reason);
            } catch (bytes memory lowLevelData) {
                console.log("- [ERROR] Part failed with low-level error");
                console.logBytes(lowLevelData);
            }
        }

        // Check final status
        (, uint256 finalExecutedParts, , bool finalIsComplete, ) = WALLET
            .getBatchSwapStatus(ORDER_HASH);

        console.log("\n=== FINAL STATUS ===");
        console.log(
            "- Executed Parts:",
            finalExecutedParts,
            "/",
            order.batchParts
        );
        console.log("- Is Complete:", finalIsComplete);

        // Check final balances
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(address(WALLET));
        uint256 oneinchBalanceAfter = IERC20(ONEINCH).balanceOf(
            address(WALLET)
        );

        console.log("\nFinal Balances:");
        console.log("- USDC before:", usdcBalanceBefore);
        console.log("- USDC after:", usdcBalanceAfter);
        console.log("- USDC used:", usdcBalanceBefore - usdcBalanceAfter);
        console.log("- 1INCH before:", oneinchBalanceBefore);
        console.log("- 1INCH after:", oneinchBalanceAfter);
        console.log(
            "- 1INCH gained:",
            oneinchBalanceAfter - oneinchBalanceBefore
        );

        vm.stopBroadcast();
    }
}
