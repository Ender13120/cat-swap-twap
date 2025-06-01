// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract RegisterBatchSwap is Script {
    // Constants
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

    // Batch parameters
    uint256 constant TOTAL_USDC = 200000; // 0.2 USDC total
    uint256 constant BATCH_PARTS = 4; // 4 parts of 0.05 USDC each
    uint256 constant TIME_BETWEEN_PARTS = 5; // 5 seconds between executions

    function run() external {
        vm.startBroadcast(USER_PK);

        console.log("=== REGISTER BATCH SWAP ORDER ===");
        console.log("Wallet:", address(WALLET));
        console.log("User:", USER);

        // Check initial balances
        uint256 initialUsdc = IERC20(USDC).balanceOf(address(WALLET));
        uint256 initialOneinch = IERC20(ONEINCH).balanceOf(address(WALLET));

        console.log("\nInitial Balances:");
        console.log("USDC:", initialUsdc);
        console.log("1INCH:", initialOneinch);

        // Set up EIP-7702 delegation
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        // Create batch order
        uint256 currentTime = block.timestamp;
        DelegatedWallet.BatchSwapOrder memory batchOrder = DelegatedWallet
            .BatchSwapOrder({
                tokenOut: USDC,
                tokenIn: ONEINCH,
                totalAmountOut: TOTAL_USDC,
                minAmountInPerPart: 0.01 ether, // Min 0.01 1INCH per part
                timestamp: currentTime,
                expiration: currentTime + 1 hours,
                orderHash: bytes32(0), // Will be generated
                batchParts: BATCH_PARTS,
                minTimeBetweenExecutions: TIME_BETWEEN_PARTS,
                maxPriceDeviation: 500, // 5%
                executorTipBps: 10, // 0.1%
                startPremiumBps: 0, // No Dutch auction
                decayRateBps: 0,
                decayInterval: 60
            });

        // Generate order hash
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

        // Sign the order
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", orderHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PK, messageHash);
        bytes memory userSig = abi.encodePacked(r, s, v);

        // Register the order
        bytes32 registeredHash = WALLET.registerBatchSwapOrder(
            batchOrder,
            userSig
        );

        console.log("\n[SUCCESS] Batch order registered!");
        console.log("Order Hash:");
        console.log(vm.toString(registeredHash));
        console.log("\nOrder Details:");
        console.log("- Total USDC: 200000 (0.2 USDC)");
        console.log("- Parts: 4 x 50000 (0.05 USDC each)");
        console.log("- Min time between parts: 5 seconds");
        console.log("- Expiration: 1 hour from now");

        console.log("\n[NEXT STEP]");
        console.log("Run ExecuteBatchPart.s.sol to execute each part");
        console.log("Wait at least 5 seconds between executions!");

        vm.stopBroadcast();
    }
}
