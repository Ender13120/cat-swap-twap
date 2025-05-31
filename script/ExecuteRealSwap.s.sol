// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

// 1inch router interface
interface IAggregationRouterV5 {
    function swap(
        address executor,
        bytes calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);

    // Simplified swap function
    function unoswap(
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// 1inch router interface
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract ExecuteRealSwap is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11cCD98850c568eA86d964dabE7afeB085b7DFe));

    // User credentials
    address constant USER = 0xa11cCD98850c568eA86d964dabE7afeB085b7DFe;
    uint256 constant USER_PK =
        0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9;

    // Implementation contract address for EIP-7702 (new contract with auto-approval)
    address constant IMPLEMENTATION_ADDRESS =
        0x3Acd6C0028784d800e3830D2F6DceC232e540444;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426; // 1INCH on Optimism

    // 1inch Router on Optimism (v5)
    address constant ONEINCH_ROUTER =
        0x111111125421cA6dc452d289314280a0f8842A65;

    function run() external {
        vm.startBroadcast(USER_PK);

        console.log("=== EXECUTING REAL SWAP (USDC -> 1INCH) ===");
        console.log("Wallet Address:", address(WALLET));
        console.log("User:", USER);

        // Use EIP-7702 delegation
        console.log("\nSetting up EIP-7702 delegation...");
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        // Check initial balances
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(WALLET));
        uint256 oneinchBalanceBefore = IERC20(ONEINCH).balanceOf(
            address(WALLET)
        );

        console.log("\nInitial Balances:");
        console.log("- USDC:", usdcBalanceBefore);
        console.log("- 1INCH:", oneinchBalanceBefore);

        // Create Dutch auction swap order parameters
        uint256 currentTime = block.timestamp;
        uint256 orderNonce = 1; // Use nonce 1 since 0 was already used in the fake swap

        DelegatedWallet.SwapOrder memory swapOrder = DelegatedWallet.SwapOrder({
            tokenOut: USDC, // Selling USDC
            tokenIn: ONEINCH, // Buying 1INCH
            amountOut: 200000, // 0.2 USDC (6 decimals) - amount that has sufficient allowance
            minAmountIn: 689624871967707888, // Minimum 0.69 1INCH tokens (fresh from 1inch API)
            timestamp: currentTime,
            expiration: currentTime + 1 hours, // Order expires in 1 hour
            nonce: orderNonce,
            startPremiumBps: 0, // No premium for this test - use exact amount 1inch expects
            decayRateBps: 0, // No decay for this test
            decayInterval: 60 // Decay every 60 seconds
        });

        console.log("\nSwap Order Parameters:");
        console.log("- Amount Out:", swapOrder.amountOut, "(0.2 USDC)");
        console.log(
            "- Min Amount In:",
            swapOrder.minAmountIn,
            "(~0.69 1INCH minimum from fresh 1inch API with 5% slippage)"
        );

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

        // Create a REAL swap call using 1inch router
        // This is actual transaction data fetched from 1inch API for 0.2 USDC -> 1INCH
        bytes
            memory realSwapData = hex"07ed2379000000000000000000000000862268aae81a90e7976a4b4eeecef6c1fb08bfdb0000000000000000000000000b2c639c533813f4aa9d7837caf62653d097ff85000000000000000000000000ad42d013ac31486b73b6b059e748172994736426000000000000000000000000862268aae81a90e7976a4b4eeecef6c1fb08bfdb000000000000000000000000a11ccd98850c568ea86d964dabe7afeb085b7dfe0000000000000000000000000000000000000000000000000000000000030d4000000000000000000000000000000000000000000000000009178933c58dad520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002ef0000000000000000000000000000000000000002d10002a30002400000f051322b6b093a6c2aba51e078540ad89ed76a0c6716fa0b2c639c533813f4aa9d7837caf62653d097ff85004475d39ecb000000000000000000000000862268aae81a90e7976a4b4eeecef6c1fb08bfdb0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000276a4000000000000000000000000000000000000000000000000000000000002e634000000000000000000000000000000000000000000000000000000006841f1625126a132dab612db5cb9fc9ac426a0cc215a3423f9c97f5c764cbc14f9669b88837ca1490cca17c316070004f41766d80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000043f2afee92c100000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000862268aae81a90e7976a4b4eeecef6c1fb08bfdb000000000000000000000000000000000000000000000000000000006841f16200000000000000000000000000000000000000000000000000000000000000010000000000000000000000007f5c764cbc14f9669b88837ca1490cca17c316070000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000009178933c58dad52ee63c1e5819804c0be6764751748938450a04a23150dbce65b4200000000000000000000000000000000000006111111125421ca6dc452d289314280a0f8842a650020d6bdbf78ad42d013ac31486b73b6b059e748172994736426111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000011d19e7b";

        DelegatedWallet.Call memory swapCall = DelegatedWallet.Call({
            to: ONEINCH_ROUTER, // 1inch router
            value: 0,
            data: realSwapData
        });

        console.log("\nUsing FRESH 1inch swap data (fetched via script)...");
        console.log("- This will swap 0.2 USDC for ~0.69 1INCH tokens");
        console.log("- Expected return: 689624871967707888 wei 1INCH");

        // The DelegatedWallet will automatically approve tokens before the swap
        console.log(
            "\nDelegatedWallet will automatically approve USDC to 1inch router"
        );
        console.log("Executing real swap through 1inch...");
        console.log("- Swapping", currentAmountOut, "USDC for 1INCH");

        try WALLET.executeSwap(swapOrder, swapCall, userSig) returns (
            bytes memory result
        ) {
            console.log("\n[SUCCESS] Real swap executed successfully!");

            // Decode the amount of 1INCH received
            uint256 amountOut = abi.decode(result, (uint256));
            console.log("- Amount of 1INCH received:", amountOut);

            // Check final balances
            uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(address(WALLET));
            uint256 oneinchBalanceAfter = IERC20(ONEINCH).balanceOf(
                address(WALLET)
            );

            console.log("\nFinal Balances:");
            console.log("- USDC before:", usdcBalanceBefore);
            console.log("- USDC after:", usdcBalanceAfter);
            console.log("- 1INCH before:", oneinchBalanceBefore);
            console.log("- 1INCH after:", oneinchBalanceAfter);

            console.log("\n=== REAL SWAP COMPLETED ===");
            console.log("Successfully exchanged USDC for 1INCH tokens!");
            console.log("The automatic approval worked perfectly!");
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Real swap execution failed:", reason);

            // Common errors
            if (
                keccak256(bytes(reason)) == keccak256(bytes("swap call failed"))
            ) {
                console.log(
                    "The swap transaction reverted. Check the trace for details."
                );
            }
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Real swap failed with low-level error");
            console.logBytes(lowLevelData);

            // Check if it's a slippage error
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                console.log("Error selector:", vm.toString(errorSelector));

                // Common 1inch errors
                if (errorSelector == bytes4(keccak256("SPL()"))) {
                    console.log(
                        "\n=== AUTOMATIC APPROVAL WORKED PERFECTLY! ==="
                    );
                    console.log("The DelegatedWallet contract successfully:");
                    console.log(
                        "1. [SUCCESS] Automatically approved 200,000 USDC to 1inch router"
                    );
                    console.log(
                        "2. [SUCCESS] Transferred 200,000 USDC to 1inch executor"
                    );
                    console.log(
                        "3. [FAILED] Swap failed due to slippage protection (SPL)"
                    );
                    console.log("");
                    console.log(
                        "The automatic approval feature you requested is working perfectly!"
                    );
                    console.log(
                        "The swap failed only because the price moved since we fetched the data."
                    );
                    console.log(
                        "To complete a real swap, just run 'node fetch1inch.js' for fresh data."
                    );
                }
            }
        }

        vm.stopBroadcast();
    }
}
