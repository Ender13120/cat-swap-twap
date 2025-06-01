// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract ExecuteBatchPart is Script {
    // Constants
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11ceB73aB7888736F264A3502933178f0a18553));

    // Sponsor credentials (for executing parts)
    address constant SPONSOR = 0xb0b4240FDD73c460736c2f65b385647f2425C68f;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426;

    // 1inch Router on Optimism
    address constant ONEINCH_ROUTER =
        0x111111125421cA6dc452d289314280a0f8842A65;

    function run() external {
        uint256 SPONSOR_PK = vm.envUint("SPONSOR_PK");
        vm.startBroadcast(SPONSOR_PK);

        // Get order hash from environment or use a default
        bytes32 orderHash;
        try vm.envBytes32("BATCH_ORDER_HASH") {
            orderHash = vm.envBytes32("BATCH_ORDER_HASH");
        } catch {
            // Default to the most recent order hash if not provided
            console.log("[INFO] No BATCH_ORDER_HASH provided, using default");
            // You can update this with your actual order hash
            orderHash = bytes32(0);
        }

        console.log("=== EXECUTE BATCH SWAP PART ===");
        console.log("Wallet:", address(WALLET));
        console.log("Executor:", SPONSOR);
        console.log("Order Hash:", vm.toString(orderHash));

        // Get order status
        (
            DelegatedWallet.BatchSwapOrder memory order,
            uint256 executedParts,
            uint256 nextExecutionTime,
            bool isComplete,
            bool isCancelled
        ) = WALLET.getBatchSwapStatus(orderHash);

        // Check if order exists
        require(order.orderHash != bytes32(0), "Order not found");
        require(!isCancelled, "Order is cancelled");
        require(!isComplete, "All parts already executed");

        console.log("\nOrder Status:");
        console.log("- Executed parts:", executedParts);
        console.log("- Remaining parts:", order.batchParts - executedParts);
        console.log("- Next part index:", executedParts);

        // Check timing
        if (block.timestamp < nextExecutionTime && executedParts > 0) {
            uint256 waitTime = nextExecutionTime - block.timestamp;
            console.log("\n[WARNING] Too early to execute next part!");
            console.log("Current time:", block.timestamp);
            console.log("Next execution time:", nextExecutionTime);
            console.log("Wait time needed:", waitTime, "seconds");
            revert("Too early to execute next part");
        }

        // Get current balances
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(WALLET));
        uint256 oneinchBefore = IERC20(ONEINCH).balanceOf(address(WALLET));

        console.log("\nPre-execution Balances:");
        console.log("- USDC:", usdcBefore);
        console.log("- 1INCH:", oneinchBefore);

        // Fetch 1inch swap data
        console.log("\nFetching 1inch swap data...");
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "fetchBatch1inch.js";
        inputs[2] = "--ffi";

        bytes memory res = vm.ffi(inputs);
        string memory output = string(res);

        // Parse the output
        (bytes memory swapData, uint256 expectedAmount) = parse1inchOutput(
            output
        );

        console.log("Expected 1INCH output:", expectedAmount);

        // Create swap call
        DelegatedWallet.Call memory swapCall = DelegatedWallet.Call({
            to: ONEINCH_ROUTER,
            value: 0,
            data: swapData
        });

        // Calculate current price
        uint256 currentPrice = (50000 * 1e18) / expectedAmount;

        // Execute the part
        console.log("\nExecuting part", executedParts, "...");
        try
            WALLET.executeBatchSwapPart(orderHash, swapCall, currentPrice)
        returns (bytes memory) {
            uint256 usdcAfter = IERC20(USDC).balanceOf(address(WALLET));
            uint256 oneinchAfter = IERC20(ONEINCH).balanceOf(address(WALLET));

            console.log("\n[SUCCESS] Part executed!");
            console.log("USDC used:", usdcBefore - usdcAfter);
            console.log("1INCH gained:", oneinchAfter - oneinchBefore);

            // Check remaining parts
            (, uint256 newExecutedParts, , , ) = WALLET.getBatchSwapStatus(
                orderHash
            );
            uint256 remainingParts = order.batchParts - newExecutedParts;

            if (remainingParts > 0) {
                console.log("\n[NEXT STEP]");
                console.log("Remaining parts:", remainingParts);
                console.log(
                    "Wait at least",
                    order.minTimeBetweenExecutions,
                    "seconds before next execution"
                );
                console.log("Run this script again to execute the next part");
            } else {
                console.log("\n[COMPLETE] All batch parts executed!");
            }
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Part execution failed:", reason);
            revert(reason);
        }

        vm.stopBroadcast();
    }

    function parse1inchOutput(
        string memory output
    ) internal pure returns (bytes memory swapData, uint256 expectedAmount) {
        bytes memory outputBytes = bytes(output);
        uint256 pipeIndex = 0;

        // Find pipe character
        for (uint256 i = 0; i < outputBytes.length; i++) {
            if (outputBytes[i] == "|") {
                pipeIndex = i;
                break;
            }
        }

        require(pipeIndex > 0, "Invalid 1inch response");

        // Extract hex data
        bytes memory hexBytes = new bytes(pipeIndex);
        for (uint256 i = 0; i < pipeIndex; i++) {
            hexBytes[i] = outputBytes[i];
        }
        swapData = vm.parseBytes(string(hexBytes));

        // Extract amount
        bytes memory amountBytes = new bytes(
            outputBytes.length - pipeIndex - 1
        );
        for (uint256 i = pipeIndex + 1; i < outputBytes.length; i++) {
            amountBytes[i - pipeIndex - 1] = outputBytes[i];
        }
        expectedAmount = vm.parseUint(string(amountBytes));
    }
}
