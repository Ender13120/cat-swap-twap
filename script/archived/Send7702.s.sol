// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Send7702Script is Script {
    /* ──────────────────────────────────────────────────────────────
       CONFIG – adjust these constants as needed
    ────────────────────────────────────────────────────────────── */

    // Basic Configuration
    address constant USDC = 0xA0B86A33E6441E6c7D3e4C5b27eaB5B2B5e6e4a0; // Example USDC address
    address constant ONEINCH_TOKEN = 0xAd42D013ac31486B73b6b059e748172994736426; // 1INCH token address
    address constant RECIPIENT = 0x742D35cc6634c0532925a3b8D4C5b27Eab5B2B5e; // Example recipient

    // Batch Execution Config
    uint256 constant TRANSFER_AMOUNT = 1 * 1e6; // 1 USDC
    uint256 constant FEE_AMOUNT = 1e12; // 0.000001 ETH worth of tokens (very small fee)
    uint256 constant TOKEN_PER_ETH = 3000 * 1e6; // 3000 USDC per ETH

    // Dutch Auction Config
    uint256 constant SWAP_AMOUNT_OUT = 1 * 1e6; // 1 USDC to sell
    uint256 constant MIN_AMOUNT_IN = 1 * 1e18; // Minimum 1 1INCH token
    uint256 constant START_PREMIUM_BPS = 200; // 2% starting premium
    uint256 constant DECAY_RATE_BPS = 10; // 0.1% decay per interval
    uint256 constant DECAY_INTERVAL = 12; // 12 seconds per decay step

    // 1inch Limit Order Config
    uint256 constant LIMIT_MAKING_AMOUNT = 1 * 1e6; // 1 USDC
    uint256 constant LIMIT_TAKING_AMOUNT = 1 * 1e18; // 1 1INCH token
    uint256 constant LIMIT_ORDER_SALT = 12345;

    // TWAP Config
    uint256 constant TWAP_MAKING_AMOUNT = 5 * 1e6; // 5 USDC total
    uint256 constant TWAP_TAKING_AMOUNT = 5 * 1e18; // 5 1INCH tokens total
    uint256 constant TWAP_PARTS = 5; // 5 executions (1 USDC each)
    uint256 constant TWAP_DURATION = 48; // 48 seconds total (12 seconds between parts)
    uint256 constant MAX_PRICE_DEVIATION = 500; // 5% max deviation
    uint256 constant EXECUTOR_TIP_BPS = 10; // 0.1% tip
    uint256 constant TWAP_SALT = 54321;

    // 1inch Protocol Address (Ethereum mainnet)
    address constant ONEINCH_LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;

    // Implementation contract address for EIP-7702
    address constant IMPLEMENTATION_ADDRESS =
        0xD3ee93e481a684ddDF7b1D768A62ce39C27dCe5C;

    function run() external {
        // Read keys from environment
        uint256 userPk = vm.envUint("USER_PK2"); // EOA that delegates
        uint256 sponsorPk = vm.envUint("SPONSOR_PK"); // Pays gas & broadcasts
        address user = vm.addr(userPk);
        address sponsor = vm.addr(sponsorPk);

        console.log("=== DelegatedWallet Comprehensive Demo ===");
        console.log("User:", user);
        console.log("Sponsor:", sponsor);
        console.log("Implementation:", IMPLEMENTATION_ADDRESS);

        // Deploy or get DelegatedWallet instance
        DelegatedWallet wallet = DelegatedWallet(payable(user));

        vm.startBroadcast(sponsorPk);

        // Attach delegation to user for EIP-7702
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, userPk);

        // 1. Demonstrate Batch Execution
        console.log("\n1. === BATCH EXECUTION DEMO ===");
        // _demonstrateBatchExecution(wallet, user, sponsor, userPk);

        // 2. Demonstrate Dutch Auction Swap
        console.log("\n2. === DUTCH AUCTION SWAP DEMO ===");
        //_demonstrateDutchAuctionSwap(wallet, user, userPk);

        // 3. Demonstrate 1inch Limit Order
        console.log("\n3. === 1INCH LIMIT ORDER DEMO ===");
        _demonstrate1inchLimitOrder(wallet, user, userPk);

        // 4. Demonstrate TWAP Order
        console.log("\n4. === TWAP ORDER DEMO ===");
        //_demonstrateTWAPOrder(wallet, user, userPk);

        // 5. Demonstrate TWAP Execution
        console.log("\n5. === TWAP EXECUTION DEMO ===");
        //_demonstrateTWAPExecution(wallet, user);

        vm.stopBroadcast();

        console.log("\n=== Demo Complete ===");
    }

    function _demonstrateBatchExecution(
        DelegatedWallet wallet,
        address user,
        address sponsor,
        uint256 userPk
    ) internal {
        // Build batch: transfer tokens to recipient
        DelegatedWallet.Call[] memory calls = new DelegatedWallet.Call[](2);

        // Call 1: Transfer USDC to recipient
        calls[0] = DelegatedWallet.Call({
            to: USDC,
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                RECIPIENT,
                TRANSFER_AMOUNT
            )
        });

        // Call 2: Approve some tokens for future use
        calls[1] = DelegatedWallet.Call({
            to: USDC,
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.approve.selector,
                address(wallet),
                type(uint256).max
            )
        });

        // Get current nonce
        uint256 currentNonce = wallet.nonce();

        // User signs operation hash
        bytes32 opHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user,
                    keccak256(abi.encode(calls)),
                    currentNonce,
                    sponsor,
                    block.chainid,
                    USDC,
                    FEE_AMOUNT,
                    TOKEN_PER_ETH
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, opHash);
        bytes memory userSig = abi.encodePacked(r, s, v);

        // Execute batch
        bytes memory data = abi.encodeWithSelector(
            DelegatedWallet.execute.selector,
            calls,
            USDC,
            FEE_AMOUNT,
            TOKEN_PER_ETH,
            userSig
        );

        (bool success, ) = user.call(data);
        require(success, "Batch execution failed");

        console.log("[SUCCESS] Batch execution successful");
        console.log("   - Transferred", TRANSFER_AMOUNT, "USDC to", RECIPIENT);
        console.log("   - Approved unlimited USDC");
        console.log("   - Paid", FEE_AMOUNT, "fee to sponsor");
    }

    function _demonstrateDutchAuctionSwap(
        DelegatedWallet wallet,
        address user,
        uint256 userPk
    ) internal {
        // Create Dutch auction swap order
        DelegatedWallet.SwapOrder memory swapOrder = DelegatedWallet.SwapOrder({
            tokenOut: USDC,
            tokenIn: ONEINCH_TOKEN,
            amountOut: SWAP_AMOUNT_OUT,
            minAmountIn: MIN_AMOUNT_IN,
            timestamp: block.timestamp,
            expiration: block.timestamp + 1 hours,
            nonce: 1001,
            startPremiumBps: START_PREMIUM_BPS,
            decayRateBps: DECAY_RATE_BPS,
            decayInterval: DECAY_INTERVAL
        });

        // Sign swap order
        bytes32 orderHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user,
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
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, orderHash);
        bytes memory swapSig = abi.encodePacked(r, s, v);

        // Get current auction price
        (uint256 currentAmountOut, uint256 timeRemaining) = wallet
            .getCurrentAuctionPrice(swapOrder);

        console.log("[SUCCESS] Dutch auction swap order created");
        console.log("   - Selling USDC for min 1INCH");
        console.log("   - Amount out:", SWAP_AMOUNT_OUT);
        console.log("   - Min amount in:", MIN_AMOUNT_IN);
        console.log("   - Current price:", currentAmountOut, "USDC");
        console.log("   - Time to min price:", timeRemaining, "seconds");
        console.log("   - Starting premium:", START_PREMIUM_BPS, "bps");
        console.log("   - Decay rate per interval:", DECAY_RATE_BPS, "bps");
        console.log("   - Decay interval:", DECAY_INTERVAL, "seconds");

        // Note: Actual execution would require a real swap call to a DEX
        console.log(
            "   [WARNING] Swap execution requires real DEX integration"
        );
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
        bytes32 registeredHash = wallet.registerLimitOrderOnChain(
            limitOrder,
            limitSig,
            ""
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

    function _demonstrateTWAPOrder(
        DelegatedWallet wallet,
        address user,
        uint256 userPk
    ) internal {
        uint256 startTime = block.timestamp + 12; // Start in 12 seconds
        uint256 endTime = startTime + TWAP_DURATION;

        // Create TWAP order
        DelegatedWallet.LimitOrder memory twapOrder = DelegatedWallet
            .LimitOrder({
                makerAsset: USDC,
                takerAsset: ONEINCH_TOKEN,
                makingAmount: TWAP_MAKING_AMOUNT,
                takingAmount: TWAP_TAKING_AMOUNT,
                salt: TWAP_SALT,
                expiration: endTime + 60, // 1 minute buffer after TWAP ends
                allowPartialFill: false, // TWAP parts should be exact
                // TWAP parameters
                twapStartTime: startTime,
                twapEndTime: endTime,
                twapParts: TWAP_PARTS,
                maxPriceDeviation: MAX_PRICE_DEVIATION,
                executorTipBps: EXECUTOR_TIP_BPS
            });

        // Sign TWAP order
        bytes32 twapOrderHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user,
                    twapOrder.makerAsset,
                    twapOrder.takerAsset,
                    twapOrder.makingAmount,
                    twapOrder.takingAmount,
                    twapOrder.salt,
                    twapOrder.expiration,
                    twapOrder.allowPartialFill,
                    block.chainid
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, twapOrderHash);
        bytes memory twapSig = abi.encodePacked(r, s, v);

        // Calculate initial price (1INCH per USDC in 18 decimals)
        uint256 initialPrice = (TWAP_TAKING_AMOUNT * 1e18) / TWAP_MAKING_AMOUNT;

        // Register TWAP order
        bytes32 registeredTwapHash = wallet.registerTWAPOrderOnChain(
            twapOrder,
            twapSig,
            initialPrice,
            ""
        );

        console.log("[SUCCESS] TWAP order registered");
        console.log("   - Order hash:", vm.toString(registeredTwapHash));
        console.log("   - Total selling USDC for 1INCH");
        console.log("   - Making amount:", TWAP_MAKING_AMOUNT);
        console.log("   - Taking amount:", TWAP_TAKING_AMOUNT);
        console.log("   - Parts:", TWAP_PARTS);
        console.log("   - Duration seconds:", TWAP_DURATION);
        console.log("   - Per part making:", TWAP_MAKING_AMOUNT / TWAP_PARTS);
        console.log("   - Per part taking:", TWAP_TAKING_AMOUNT / TWAP_PARTS);
        console.log("   - Max price deviation:", MAX_PRICE_DEVIATION, "bps");
        console.log("   - Executor tip:", EXECUTOR_TIP_BPS, "bps");
        console.log("   - Initial price:", initialPrice);
        console.log("   - Interval between parts: 12 seconds");

        // Get TWAP status
        (
            DelegatedWallet.LimitOrder memory storedOrder,
            uint256 executedParts,
            uint256 nextExecutionTime,
            bool isComplete
        ) = wallet.getTWAPStatus(registeredTwapHash);

        console.log("   - Executed parts:", executedParts);
        console.log("   - Total parts:", storedOrder.twapParts);
        console.log("   - Next execution:", nextExecutionTime);
        console.log("   - Complete:", isComplete);
    }

    function _demonstrateTWAPExecution(
        DelegatedWallet wallet,
        address user
    ) internal {
        // This would typically be called by bots/executors
        address executorWallet = address(
            0x1234567890123456789012345678901234567890
        );

        console.log("[SUCCESS] TWAP execution demo");
        console.log("   - Executor wallet:", executorWallet);
        console.log("   - Would call executeTWAPPart() with:");
        console.log("     * orderHash: [TWAP order hash]");
        console.log("     * partIndex: 0 (first part)");
        console.log("     * currentPrice: [current market price]");
        console.log("     * integratorWallet:", executorWallet);
        console.log("   - 1inch would automatically:");
        console.log("     * Fill the order atomically");
        console.log("     * Pay main amount to contract");
        console.log("     * Pay integrator fee to executor");
        console.log("     * Trigger onTWAPPartFilled callback");

        // Note: Actual execution would require:
        // 1. A registered TWAP order
        // 2. Proper timing (after twapStartTime)
        // 3. Valid current price
        // 4. Integration with 1inch API for order submission

        console.log(
            "   [WARNING] Full execution requires 1inch API integration"
        );
    }
}
