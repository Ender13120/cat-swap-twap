// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Step3LimitOrderScript is Script {
    /* ──────────────────────────────────────────────────────────────
       CONFIG – adjust these constants as needed
    ────────────────────────────────────────────────────────────── */

    // Real Ethereum mainnet token addresses
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // Real USDC on Ethereum mainnet
    address constant ONEINCH_TOKEN = 0x111111111117dC0aa78b770fA6A738034120C302; // Real 1INCH token on mainnet

    // 1inch Limit Order Config
    uint256 constant LIMIT_MAKING_AMOUNT = 1 * 1e6; // 1 USDC
    uint256 constant LIMIT_TAKING_AMOUNT = 1 * 1e18; // 1 1INCH token
    uint256 constant LIMIT_ORDER_SALT = 12345;

    // Implementation contract address for EIP-7702 (deployed on Ethereum mainnet)
    address constant IMPLEMENTATION_ADDRESS =
        0xD3ee93e481a684ddDF7b1D768A62ce39C27dCe5C;

    function run() external {
        // Read keys from environment
        uint256 userPk = vm.envUint("USER_PK2"); // EOA that delegates
        uint256 sponsorPk = vm.envUint("SPONSOR_PK"); // Pays gas & broadcasts
        address user = vm.addr(userPk);
        address sponsor = vm.addr(sponsorPk);

        console.log("=== Step 3: 1INCH LIMIT ORDER DEMO ===");
        console.log("User:", user);
        console.log("Sponsor:", sponsor);
        console.log("Implementation:", IMPLEMENTATION_ADDRESS);

        // Deploy or get DelegatedWallet instance
        DelegatedWallet wallet = DelegatedWallet(payable(user));

        vm.startBroadcast(sponsorPk);

        // Attach delegation to user for EIP-7702
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, userPk);

        // Demonstrate 1inch Limit Order
        console.log("\n=== 1INCH LIMIT ORDER DEMO ===");
        _demonstrate1inchLimitOrder(wallet, user, userPk);

        vm.stopBroadcast();

        console.log("\n=== Step 3 Complete ===");
    }

    function _demonstrate1inchLimitOrder(
        DelegatedWallet wallet,
        address user,
        uint256 userPk
    ) internal {
        // Create limit order
        DelegatedWallet.LimitOrder memory limitOrder = DelegatedWallet
            .LimitOrder({
                makerAsset: USDC,
                takerAsset: ONEINCH_TOKEN,
                makingAmount: LIMIT_MAKING_AMOUNT,
                takingAmount: LIMIT_TAKING_AMOUNT,
                salt: LIMIT_ORDER_SALT,
                expiration: block.timestamp + 24 hours,
                allowPartialFill: true,
                // TWAP parameters (not used for regular limit orders)
                twapStartTime: 0,
                twapEndTime: 0,
                twapParts: 0,
                maxPriceDeviation: 0,
                executorTipBps: 0
            });

        // Sign limit order
        bytes32 limitOrderHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user,
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
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, limitOrderHash);
        bytes memory limitSig = abi.encodePacked(r, s, v);

        // Register limit order
        bytes32 registeredHash = wallet.registerLimitOrder(
            limitOrder,
            limitSig
        );

        console.log("[SUCCESS] 1inch limit order registered");
        console.log("   - Order hash:", vm.toString(registeredHash));
        console.log("   - Selling USDC for 1INCH");
        console.log("   - Making amount:", LIMIT_MAKING_AMOUNT);
        console.log("   - Taking amount:", LIMIT_TAKING_AMOUNT);
        console.log(
            "   - Partial fills:",
            limitOrder.allowPartialFill ? "allowed" : "not allowed"
        );
        console.log("   - Expires in 24 hours");

        // Check order status
        (bool isRegistered, bool isCancelled) = wallet.getLimitOrderStatus(
            registeredHash
        );
        console.log("   - Status registered:", isRegistered);
        console.log("   - Status cancelled:", isCancelled);
    }
}
