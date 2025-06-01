// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../../src/Firstdraft.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract RegisterBatchSwap is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11ceB73aB7888736F264A3502933178f0a18553));

    // User credentials (for signing the batch order)
    address constant USER = 0xa11ceB73aB7888736F264A3502933178f0a18553;
    uint256 constant USER_PK =
        0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9;

    // Implementation contract address for EIP-7702
    address constant IMPLEMENTATION_ADDRESS =
        0x6B90FAF6d634EDE2E56c024A9b852A9607a5c7bf;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426;

    function run() external {
        vm.startBroadcast(USER_PK);

        console.log("=== REGISTERING BATCH SWAP ORDER ===");
        console.log("Wallet Address:", address(WALLET));
        console.log("User:", USER);

        // Use EIP-7702 delegation
        console.log("\nSetting up EIP-7702 delegation...");
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        // Check balances
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(WALLET));
        uint256 oneinchBalance = IERC20(ONEINCH).balanceOf(address(WALLET));

        console.log("\nCurrent Balances:");
        console.log("- USDC:", usdcBalance);
        console.log("- 1INCH:", oneinchBalance);

        // Create batch swap order parameters
        uint256 currentTime = block.timestamp;
        DelegatedWallet.BatchSwapOrder memory batchOrder = DelegatedWallet
            .BatchSwapOrder({
                tokenOut: USDC,
                tokenIn: ONEINCH,
                totalAmountOut: 200000, // 0.2 USDC total (4 parts of 0.05 each)
                minAmountInPerPart: 0.01 ether, // Minimum 1INCH per part
                timestamp: currentTime,
                expiration: currentTime + 1 hours,
                orderHash: bytes32(0),
                batchParts: 4,
                minTimeBetweenExecutions: 5, // 5 seconds
                maxPriceDeviation: 500, // 5%
                executorTipBps: 10, // 0.1%
                startPremiumBps: 0,
                decayRateBps: 0,
                decayInterval: 60
            });

        console.log("\nBatch Swap Order Parameters:");
        console.log(
            "- Total Amount Out:",
            batchOrder.totalAmountOut,
            "(0.2 USDC)"
        );
        console.log("- Batch Parts:", batchOrder.batchParts);
        console.log(
            "- Min Time Between Executions:",
            batchOrder.minTimeBetweenExecutions,
            "seconds"
        );

        // Create order hash and signature
        bytes32 orderHash = keccak256(
            abi.encode(
                batchOrder.tokenOut,
                batchOrder.tokenIn,
                batchOrder.totalAmountOut,
                batchOrder.minAmountInPerPart,
                batchOrder.timestamp,
                batchOrder.expiration,
                batchOrder.batchParts,
                batchOrder.minTimeBetweenExecutions,
                batchOrder.maxPriceDeviation,
                batchOrder.executorTipBps,
                batchOrder.startPremiumBps,
                batchOrder.decayRateBps,
                batchOrder.decayInterval,
                block.chainid,
                address(WALLET)
            )
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", orderHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PK, messageHash);
        bytes memory userSig = abi.encodePacked(r, s, v);

        console.log("\nRegistering batch swap order...");
        console.log("- Order Hash:", vm.toString(orderHash));

        try WALLET.registerBatchSwapOrder(batchOrder, userSig) returns (
            bytes32 registeredOrderHash
        ) {
            console.log("\n[SUCCESS] Batch swap order registered!");
            console.log(
                "- Registered Order Hash:",
                vm.toString(registeredOrderHash)
            );

            // Verify the registration
            (
                DelegatedWallet.BatchSwapOrder memory order,
                uint256 executedParts,
                uint256 nextExecutionTime,
                bool isComplete,
                bool isCancelled
            ) = WALLET.getBatchSwapStatus(registeredOrderHash);

            console.log("\nBatch Order Status:");
            console.log(
                "- Executed Parts:",
                executedParts,
                "/",
                order.batchParts
            );
            console.log("- Is Complete:", isComplete);
            console.log("- Is Cancelled:", isCancelled);
            console.log("- Next Execution Time:", nextExecutionTime);

            console.log("\n=== BATCH ORDER READY FOR EXECUTION ===");
            console.log(
                "Order hash to use for execution:",
                vm.toString(registeredOrderHash)
            );
            console.log(
                "Anyone can now execute parts with executeBatchSwapPart()"
            );
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Batch order registration failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(
                "\n[ERROR] Batch order registration failed with low-level error"
            );
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
