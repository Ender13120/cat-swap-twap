// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../../src/Firstdraft.sol";

contract ExecuteSwap is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11ceB73aB7888736F264A3502933178f0a18553));

    // User credentials
    address constant USER = 0xa11ceB73aB7888736F264A3502933178f0a18553;
    uint256 constant USER_PK =
        0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9;

    // Executor (the one running this script)
    address constant EXECUTOR = 0xb0b4240FDD73c460736c2f65b385647f2425C68f;

    // Implementation contract address for EIP-7702
    address constant IMPLEMENTATION_ADDRESS =
        0xa6b325a8Ba148E17C5e420fD41714CfEA5c9938d;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426; // 1INCH on Optimism

    // 1inch Router on Optimism (for the actual swap execution)
    address constant ONEINCH_ROUTER =
        0x111111125421cA6dc452d289314280a0f8842A65;

    function run() external {
        vm.startBroadcast(USER_PK);

        console.log("=== EXECUTING DUTCH AUCTION SWAP ===");
        console.log("Wallet Address:", address(WALLET));
        console.log("User:", USER);
        console.log("Executor:", EXECUTOR);

        // Use EIP-7702 delegation
        console.log("\nSetting up EIP-7702 delegation...");
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        // Create Dutch auction swap order parameters
        uint256 currentTime = block.timestamp;
        uint256 orderNonce = WALLET.nonce();

        DelegatedWallet.SwapOrder memory swapOrder = DelegatedWallet.SwapOrder({
            tokenOut: USDC, // Selling USDC
            tokenIn: ONEINCH, // Buying 1INCH
            amountOut: 1000000, // 1 USDC (6 decimals)
            minAmountIn: 0, // Set to 0 for testing - in reality this would be the minimum 1INCH expected
            timestamp: currentTime,
            expiration: currentTime + 1 hours, // Order expires in 1 hour
            nonce: orderNonce,
            startPremiumBps: 200, // Start with 2% premium (pay extra to guarantee execution)
            decayRateBps: 10, // Decay by 0.1% every interval
            decayInterval: 60 // Decay every 60 seconds
        });

        console.log("\nSwap Order Parameters:");
        console.log("- Token Out (USDC):", swapOrder.tokenOut);
        console.log("- Token In (1INCH):", swapOrder.tokenIn);
        console.log("- Amount Out:", swapOrder.amountOut, "(1 USDC)");
        console.log(
            "- Min Amount In:",
            swapOrder.minAmountIn,
            "(0 for testing - no tokens required)"
        );
        console.log("- Start Premium:", swapOrder.startPremiumBps, "bps (2%)");
        console.log(
            "- Decay Rate:",
            swapOrder.decayRateBps,
            "bps per interval (0.1%)"
        );
        console.log("- Decay Interval:", swapOrder.decayInterval, "seconds");
        console.log("- Expiration:", swapOrder.expiration);

        // Calculate current Dutch auction price
        (uint256 currentAmountOut, uint256 timeRemaining) = WALLET
            .getCurrentAuctionPrice(swapOrder);
        console.log("\nCurrent Dutch Auction Status:");
        console.log("- Current Amount Out Required:", currentAmountOut);
        console.log("- Time until minimum price:", timeRemaining, "seconds");

        // Create user signature for the swap order
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        address(WALLET),
                        swapOrder.tokenOut,
                        swapOrder.tokenIn,
                        swapOrder.amountOut,
                        swapOrder.minAmountIn,
                        swapOrder.timestamp,
                        swapOrder.expiration,
                        swapOrder.nonce,
                        block.chainid,
                        keccak256(
                            abi.encode(
                                swapOrder.startPremiumBps,
                                swapOrder.decayRateBps,
                                swapOrder.decayInterval
                            )
                        )
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PK, messageHash);
        bytes memory userSig = abi.encodePacked(r, s, v);

        // Create a realistic swap call that transfers USDC from the contract
        // In a real implementation, this would be a call to a DEX router
        // For testing, we'll transfer USDC and assume the swap works

        // First, let's check balances
        console.log("\nChecking token balances before swap:");

        // For demo purposes, let's just transfer some USDC to simulate a swap
        // This simulates selling USDC (real DEX would give us 1INCH back)
        DelegatedWallet.Call memory swapCall = DelegatedWallet.Call({
            to: USDC, // Call the USDC token contract
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                EXECUTOR, // Transfer to executor as a fee/tip
                currentAmountOut // Transfer the amount we're "selling"
            )
        });

        console.log("\nExecuting Dutch auction swap...");
        console.log("- Swap call target:", swapCall.to);
        console.log("- Current amount out required:", currentAmountOut);

        try WALLET.executeSwap(swapOrder, swapCall, userSig) returns (
            bytes memory result
        ) {
            console.log("\n[SUCCESS] Swap executed successfully!");
            console.logBytes(result);

            // Check new nonce
            uint256 newNonce = WALLET.nonce();
            console.log("- Old nonce:", orderNonce);
            console.log("- New nonce:", newNonce);

            console.log("\n=== SWAP COMPLETED ===");
            console.log("Dutch auction swap executed at current market price");
            console.log("Amount sold:", currentAmountOut, "USDC");
            console.log(
                "Minimum amount expected:",
                swapOrder.minAmountIn,
                "1INCH"
            );
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Swap execution failed:", reason);

            // Provide specific guidance for common errors
            if (
                keccak256(bytes(reason)) ==
                keccak256(bytes("Order already executed"))
            ) {
                console.log("Suggestion: Try with a different nonce");
            } else if (
                keccak256(bytes(reason)) == keccak256(bytes("Order expired"))
            ) {
                console.log(
                    "Suggestion: Create a new order with later expiration"
                );
            } else {
                console.log("Check order parameters and signature");
            }
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Swap failed with low-level error");
            console.logBytes(lowLevelData);

            // Try to decode common revert reasons
            if (lowLevelData.length >= 4) {
                bytes4 selector = bytes4(lowLevelData);
                console.log("Error selector:", vm.toString(selector));

                // Check for known error selectors
                if (selector == DelegatedWallet.BadSignature.selector) {
                    console.log("Error: Bad signature - check user signature");
                } else if (selector == DelegatedWallet.OrderExpired.selector) {
                    console.log("Error: Order has expired");
                } else if (
                    selector == DelegatedWallet.OrderAlreadyExecuted.selector
                ) {
                    console.log("Error: Order has already been executed");
                } else if (
                    selector == DelegatedWallet.InsufficientReturn.selector
                ) {
                    console.log("Error: Insufficient return from swap");
                }
            }
        }

        vm.stopBroadcast();
    }

    // Helper function to get a real 1inch swap call
    // In practice, you'd call the 1inch API to get the swap data
    function _get1inchSwapCall(
        uint256 amountOut,
        uint256 minAmountIn
    ) internal pure returns (DelegatedWallet.Call memory) {
        // This is a placeholder - in reality you'd:
        // 1. Call 1inch API with: fromToken=USDC, toToken=1INCH, amount=amountOut
        // 2. Get the swap transaction data
        // 3. Return it as a Call struct

        return
            DelegatedWallet.Call({
                to: ONEINCH_ROUTER,
                value: 0,
                data: abi.encodeWithSignature(
                    "swap(address,uint256,uint256,address)",
                    USDC,
                    amountOut,
                    minAmountIn,
                    address(WALLET)
                )
            });
    }
}
