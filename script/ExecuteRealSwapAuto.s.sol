// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ExecuteRealSwapAuto is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11cCD98850c568eA86d964dabE7afeB085b7DFe));

    // User credentials
    address constant USER = 0xa11cCD98850c568eA86d964dabE7afeB085b7DFe;
    //@TODO: Add USER_PK=0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9 to .env file
    // uint256 USER_PK loaded in run() function

    // Implementation contract address for EIP-7702 (new contract with auto-approval)
    address constant IMPLEMENTATION_ADDRESS =
        0x6B90FAF6d634EDE2E56c024A9b852A9607a5c7bf;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426; // 1INCH on Optimism

    // 1inch Router on Optimism (v5)
    address constant ONEINCH_ROUTER =
        0x111111125421cA6dc452d289314280a0f8842A65;

    function run() external {
        uint256 USER_PK = vm.envUint("USER_PK");
        vm.startBroadcast(USER_PK);

        console.log(
            "=== EXECUTING REAL SWAP WITH AUTO-FETCH (USDC -> 1INCH) ==="
        );
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

        // Fetch fresh 1inch swap data using FFI
        console.log("\nFetching fresh 1inch swap data...");
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "fetch1inch.js";
        inputs[2] = "--ffi";

        bytes memory res = vm.ffi(inputs);
        string memory output = string(res);

        // Parse the output (format: hexData|dstAmount)
        bytes memory swapData;
        uint256 expectedAmount;

        // Find the pipe character
        bytes memory outputBytes = bytes(output);
        uint256 pipeIndex = 0;
        for (uint256 i = 0; i < outputBytes.length; i++) {
            if (outputBytes[i] == "|") {
                pipeIndex = i;
                break;
            }
        }

        if (
            pipeIndex == 0 ||
            bytes(output).length == 0 ||
            keccak256(bytes(output)) == keccak256(bytes("ERROR"))
        ) {
            revert("Failed to fetch 1inch data");
        }

        // Extract hex data and expected amount
        bytes memory hexBytes = new bytes(pipeIndex);
        for (uint256 i = 0; i < pipeIndex; i++) {
            hexBytes[i] = outputBytes[i];
        }

        // Convert hex string to bytes
        swapData = vm.parseBytes(string(hexBytes));

        // Extract expected amount
        bytes memory amountBytes = new bytes(
            outputBytes.length - pipeIndex - 1
        );
        for (uint256 i = pipeIndex + 1; i < outputBytes.length; i++) {
            amountBytes[i - pipeIndex - 1] = outputBytes[i];
        }
        expectedAmount = vm.parseUint(string(amountBytes));

        console.log("Fresh data fetched successfully!");
        console.log("- Expected 1INCH output:", expectedAmount);
        console.log("- Swap data length:", swapData.length);

        // Fetch current nonce on-chain and find a unique one for swap orders
        uint256 currentTime = block.timestamp;
        uint256 orderNonce;

        // Check the general nonce from the contract
        uint256 baseNonce = WALLET.nonce();
        console.log("\nFetching nonce on-chain...");
        console.log("- Base contract nonce:", baseNonce);

        // Find an unused nonce for swap orders (starting from baseNonce)
        orderNonce = baseNonce;
        while (WALLET.executedOrders(orderNonce)) {
            console.log("- Nonce", orderNonce, "already used, trying next...");
            orderNonce++;
        }
        console.log("- Using nonce:", orderNonce);

        DelegatedWallet.SwapOrder memory swapOrder = DelegatedWallet.SwapOrder({
            tokenOut: USDC, // Selling USDC
            tokenIn: ONEINCH, // Buying 1INCH
            amountOut: 200000, // 0.2 USDC (6 decimals)
            minAmountIn: (expectedAmount * 95) / 100, // 5% slippage tolerance
            timestamp: currentTime,
            expiration: currentTime + 1 hours, // Order expires in 1 hour
            nonce: orderNonce,
            startPremiumBps: 0, // No premium for this test - use exact amount 1inch expects
            decayRateBps: 0, // No decay for this test
            decayInterval: 60 // Decay every 60 seconds
        });

        console.log("\nSwap Order Parameters:");
        console.log("- Nonce:", swapOrder.nonce);
        console.log("- Amount Out:", swapOrder.amountOut, "(0.2 USDC)");
        console.log(
            "- Min Amount In:",
            swapOrder.minAmountIn,
            "(with 5% slippage tolerance)"
        );

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

        // Create the swap call with fresh data
        DelegatedWallet.Call memory swapCall = DelegatedWallet.Call({
            to: ONEINCH_ROUTER, // 1inch router
            value: 0,
            data: swapData
        });

        console.log("\nExecuting real swap with fresh 1inch data...");
        console.log("- The DelegatedWallet will automatically approve USDC");
        console.log(
            "- Swapping 0.2 USDC for ~",
            expectedAmount / 1e18,
            "1INCH"
        );

        try WALLET.executeSwap(swapOrder, swapCall, userSig) returns (
            bytes memory result
        ) {
            console.log("\n[SUCCESS] Real swap executed successfully!");

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
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Real swap failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
