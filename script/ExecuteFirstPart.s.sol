// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract ExecuteFirstPart is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11ceB73aB7888736F264A3502933178f0a18553));

    // Sponsor credentials (who pays gas and executes)
    address constant SPONSOR = 0xb0b4240FDD73c460736c2f65b385647f2425C68f;
    // !PLACEHOLDER! - Private key removed for security
    // Load from environment variable instead:
    // uint256 SPONSOR_PK = vm.envUint("SPONSOR_PK");

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
        // Load private key from environment
        uint256 SPONSOR_PK = vm.envUint("SPONSOR_PK");

        vm.startBroadcast(SPONSOR_PK);

        console.log("=== EXECUTING FIRST BATCH SWAP PART ===");
        console.log("Wallet Address:", address(WALLET));
        console.log("Executor (Sponsor):", SPONSOR);
        console.log("Order Hash:", vm.toString(ORDER_HASH));

        // Check status
        (
            DelegatedWallet.BatchSwapOrder memory order,
            uint256 executedParts,
            uint256 nextExecutionTime,
            bool isComplete,
            bool isCancelled
        ) = WALLET.getBatchSwapStatus(ORDER_HASH);

        console.log("\nBatch Order Status:");
        console.log("- Executed Parts:", executedParts, "/", order.batchParts);
        console.log("- Next Execution Time:", nextExecutionTime);
        console.log("- Current Time:", block.timestamp);

        if (executedParts >= order.batchParts) {
            console.log("\n[INFO] All parts already executed!");
            vm.stopBroadcast();
            return;
        }

        if (block.timestamp < nextExecutionTime && executedParts > 0) {
            uint256 waitTime = nextExecutionTime - block.timestamp;
            console.log(
                "\n[INFO] Need to wait",
                waitTime,
                "seconds before next execution"
            );
            console.log(
                "Next execution available at timestamp:",
                nextExecutionTime
            );
            vm.stopBroadcast();
            return;
        }

        // Check balances
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(WALLET));
        uint256 oneinchBefore = IERC20(ONEINCH).balanceOf(address(WALLET));

        console.log("\nBalances Before:");
        console.log("- USDC:", usdcBefore);
        console.log("- 1INCH:", oneinchBefore);

        // Fetch fresh 1inch swap data
        console.log("\nFetching fresh 1inch swap data...");
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

        require(pipeIndex > 0, "Failed to fetch 1inch data");

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
        uint256 currentPrice = (50000 * 1e18) / expectedAmount;

        console.log(
            "\nExecuting part",
            executedParts + 1,
            "of",
            order.batchParts
        );
        console.log("...");

        try
            WALLET.executeBatchSwapPart(ORDER_HASH, swapCall, currentPrice)
        returns (bytes memory result) {
            console.log("\n[SUCCESS] Part executed!");

            // Check balances after
            uint256 usdcAfter = IERC20(USDC).balanceOf(address(WALLET));
            uint256 oneinchAfter = IERC20(ONEINCH).balanceOf(address(WALLET));

            console.log("\nBalances After:");
            console.log("- USDC used:", usdcBefore - usdcAfter);
            console.log("- 1INCH gained:", oneinchAfter - oneinchBefore);

            // Check new status
            (, uint256 newExecutedParts, uint256 newNextTime, , ) = WALLET
                .getBatchSwapStatus(ORDER_HASH);
            console.log("\nNew Status:");
            console.log(
                "- Executed Parts:",
                newExecutedParts,
                "/",
                order.batchParts
            );
            if (newExecutedParts < order.batchParts) {
                console.log("- Next Execution Time:", newNextTime);
                console.log(
                    "- Wait Time:",
                    newNextTime > block.timestamp
                        ? newNextTime - block.timestamp
                        : 0,
                    "seconds"
                );
            }
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Part execution failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Part failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
