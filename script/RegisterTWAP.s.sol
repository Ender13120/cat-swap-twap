// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

contract RegisterTWAP is Script {
    // Use the user address directly since EIP-7702 stores state there
    DelegatedWallet constant WALLET =
        DelegatedWallet(payable(0xa11ceB73aB7888736F264A3502933178f0a18553));

    // User address (should be the one that created the order)
    address constant USER = 0xa11ceB73aB7888736F264A3502933178f0a18553;
    uint256 constant USER_PK =
        0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9;

    // Implementation contract address for EIP-7702 (newly deployed with simplified validation)
    address constant IMPLEMENTATION_ADDRESS =
        0xE92a890a2Bf4105e7240e0a6465141FA1fA7530D;

    // Token addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
    address constant ONEINCH = 0xAd42D013ac31486B73b6b059e748172994736426; // 1INCH on Optimism

    function run() external {
        vm.startBroadcast(USER_PK);

        console.log("=== REGISTERING TWAP ORDER ON-CHAIN ===");
        console.log("Contract Address:", address(WALLET));
        console.log("Implementation:", IMPLEMENTATION_ADDRESS);
        console.log("User:", USER);

        // Use EIP-7702 delegation
        console.log("\nSetting up EIP-7702 delegation...");
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, USER_PK);

        // Create TWAP order parameters
        uint256 currentTime = block.timestamp;
        DelegatedWallet.LimitOrder memory limitOrder = DelegatedWallet
            .LimitOrder({
                makerAsset: USDC,
                takerAsset: ONEINCH,
                makingAmount: 1000000, // 1 USDC (6 decimals)
                takingAmount: 20000000000000000000, // 20 1INCH tokens (18 decimals)
                salt: uint256(keccak256(abi.encode(USER, currentTime))),
                expiration: currentTime + 1 days, // 24 hours from now
                allowPartialFill: false,
                // TWAP Parameters
                twapStartTime: currentTime, // Start immediately
                twapEndTime: currentTime + 1 hours, // End in 1 hour
                twapParts: 5, // 5 parts = 12 minutes between each part
                maxPriceDeviation: 500, // 5% max price deviation
                executorTipBps: 50 // 0.5% tip for executors
            });

        console.log("\nTWAP Order Parameters:");
        console.log("- Maker Asset (USDC):", limitOrder.makerAsset);
        console.log("- Taker Asset (1INCH):", limitOrder.takerAsset);
        console.log("- Making Amount:", limitOrder.makingAmount, "(1 USDC)");
        console.log("- Taking Amount:", limitOrder.takingAmount, "(20 1INCH)");
        console.log("- TWAP Parts:", limitOrder.twapParts);
        console.log(
            "- Duration:",
            (limitOrder.twapEndTime - limitOrder.twapStartTime) / 60,
            "minutes"
        );
        console.log(
            "- Interval:",
            (limitOrder.twapEndTime - limitOrder.twapStartTime) /
                limitOrder.twapParts /
                60,
            "minutes per part"
        );

        // Create user signature for the order
        bytes32 orderHash = keccak256(
            abi.encode(limitOrder, block.chainid, address(WALLET))
        );

        // Sign the order hash (this would normally be done by the user)
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        address(WALLET),
                        limitOrder.makerAsset,
                        limitOrder.takerAsset,
                        limitOrder.makingAmount,
                        limitOrder.takingAmount,
                        limitOrder.salt,
                        limitOrder.expiration,
                        limitOrder.allowPartialFill,
                        block.chainid
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PK, messageHash);
        bytes memory userSig = abi.encodePacked(r, s, v);

        // Initial price for price protection (takingAmount per makingAmount in 18 decimals)
        uint256 initialPrice = (limitOrder.takingAmount * 1e18) /
            limitOrder.makingAmount;

        console.log("\nRegistering TWAP order...");
        console.log("Expected order hash:", vm.toString(orderHash));

        try
            WALLET.registerTWAPOrderOnChain(
                limitOrder,
                userSig,
                initialPrice,
                bytes("") // Empty extension
            )
        returns (bytes32 registeredOrderHash) {
            console.log("\n[SUCCESS] TWAP order registered on-chain!");
            console.log("Order Hash:", vm.toString(registeredOrderHash));
            console.log("Initial Price:", initialPrice);

            // Get the status to verify
            (
                DelegatedWallet.LimitOrder memory order,
                uint256 executedParts,
                uint256 nextExecutionTime,
                bool isComplete
            ) = WALLET.getTWAPStatus(registeredOrderHash);

            console.log("\nOrder Status:");
            console.log("- Total Parts:", order.twapParts);
            console.log("- Executed Parts:", executedParts);
            console.log("- Next Execution Time:", nextExecutionTime);
            console.log("- Is Complete:", isComplete);

            console.log("\n=== NEXT STEPS ===");
            console.log("1. Update ExecuteTWAP.s.sol with this order hash:");
            console.log("   ORDER_HASH =", vm.toString(registeredOrderHash));
            console.log("2. Run the ExecuteTWAP script to execute parts");
            console.log(
                "3. Each part can be executed every",
                (order.twapEndTime - order.twapStartTime) /
                    order.twapParts /
                    60,
                "minutes"
            );
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Registration failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Registration failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
