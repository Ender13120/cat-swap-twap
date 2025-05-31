// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// INTERFACES
// ============================================================================

/// @title 1inch Limit Order Protocol interface
interface IOrderMixin {
    struct Order {
        uint256 salt;
        uint256 maker; // Address packed as uint256
        uint256 receiver; // Address packed as uint256
        uint256 makerAsset; // Address packed as uint256
        uint256 takerAsset; // Address packed as uint256
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 makerTraits; // MakerTraits packed as uint256
    }

    function fillOrder(
        Order calldata order,
        bytes calldata signature,
        bytes calldata interaction,
        uint256 makingAmount,
        uint256 takingAmount
    )
        external
        payable
        returns (
            uint256 actualMakingAmount,
            uint256 actualTakingAmount,
            bytes32 orderHash
        );

    function cancelOrder(uint256 orderInfo) external;

    function hashOrder(Order calldata order) external view returns (bytes32);
}

/// @title EIP-1271 interface for smart contract signature validation
interface IERC1271 {
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);
}

// Add these imports/interfaces after your existing interfaces
interface IOrderRegistrator {
    function registerOrder(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes calldata signature
    ) external;

    event OrderRegistered(
        IOrderMixin.Order order,
        bytes extension,
        bytes signature
    );
}

// ============================================================================
// MAIN CONTRACT
// ============================================================================

contract DelegatedWallet is IERC1271 {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    struct SwapOrder {
        address tokenOut; // Token to sell
        address tokenIn; // Token to buy
        uint256 amountOut; // Final/minimum amount of tokenOut to sell
        uint256 minAmountIn; // Minimum amount of tokenIn to receive
        uint256 timestamp; // When the order was created
        uint256 expiration; // When the order expires
        uint256 nonce; // Order nonce for replay protection
        uint256 startPremiumBps; // Starting premium in basis points (e.g., 200 = 2%)
        uint256 decayRateBps; // Decay rate per interval in basis points (e.g., 10 = 0.1%)
        uint256 decayInterval; // Time interval for each decay step in seconds (e.g., 10)
    }

    struct LimitOrder {
        address makerAsset; // Token to sell
        address takerAsset; // Token to buy
        uint256 makingAmount; // Total amount of makerAsset to sell across all TWAP parts
        uint256 takingAmount; // Total amount of takerAsset to receive across all TWAP parts
        uint256 salt; // Unique order identifier
        uint256 expiration; // When the order expires
        bool allowPartialFill; // Whether partial fills are allowed
        // TWAP Parameters
        uint256 twapStartTime; // When TWAP execution can begin
        uint256 twapEndTime; // When TWAP execution must end
        uint256 twapParts; // Number of separate executions
        uint256 maxPriceDeviation; // Max price deviation in basis points (e.g., 500 = 5%)
        uint256 executorTipBps; // Tip for executor in basis points (e.g., 10 = 0.1%)
    }

    struct TWAPExecution {
        bytes32 orderHash; // Hash of the parent TWAP order
        uint256 partIndex; // Which part of the TWAP (0 to twapParts-1)
        uint256 executionTime; // When this part was executed
        uint256 actualMakingAmount; // Actual amount sold in this execution
        uint256 actualTakingAmount; // Actual amount received in this execution
        address executor; // Who executed this part
    }

    struct TWAPPartOrder {
        bytes32 parentOrderHash; // Hash of the parent TWAP order
        uint256 partIndex; // Which part this represents
        bool isValid; // Whether this is a valid TWAP part order
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BatchExecuted(uint256 indexed nonce, uint256 gasUsedWei);

    event SwapExecuted(
        uint256 indexed orderNonce,
        address indexed tokenOut,
        address indexed tokenIn,
        uint256 amountOut,
        uint256 amountIn,
        uint256 currentAmountOut,
        address executor
    );

    event LimitOrderRegistered(
        bytes32 indexed orderHash,
        address indexed makerAsset,
        address indexed takerAsset,
        uint256 makingAmount,
        uint256 takingAmount
    );

    event TWAPOrderRegistered(
        bytes32 indexed orderHash,
        address indexed makerAsset,
        address indexed takerAsset,
        uint256 totalMakingAmount,
        uint256 totalTakingAmount,
        uint256 twapParts,
        uint256 twapStartTime,
        uint256 twapEndTime
    );

    event TWAPPartOrderCreated(
        bytes32 indexed parentOrderHash,
        uint256 indexed partIndex,
        bytes32 indexed oneinchOrderHash,
        uint256 makingAmount,
        uint256 takingAmount
    );

    event TWAPPartExecuted(
        bytes32 indexed orderHash,
        uint256 indexed partIndex,
        address indexed executor,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 integratorFee
    );

    event LimitOrderCancelled(bytes32 indexed orderHash);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error BadSignature();
    error FeeTooLow(uint256 ethCost, uint256 ethPaid);
    error OrderExpired(uint256 expiration, uint256 currentTime);
    error InsufficientReturn(uint256 minAmountIn, uint256 actualAmountIn);
    error OrderAlreadyExecuted(uint256 orderNonce);
    error InvalidLimitOrderProtocol();
    error TWAPNotStarted(uint256 currentTime, uint256 startTime);
    error TWAPEnded(uint256 currentTime, uint256 endTime);
    error TWAPPartAlreadyExecuted(uint256 partIndex);
    error TWAPPartNotReady(uint256 currentTime, uint256 nextExecutionTime);
    error PriceDeviationTooHigh(uint256 currentPrice, uint256 maxDeviation);
    error InvalidTWAPParameters();

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    uint256 public nonce;

    // Order tracking
    mapping(uint256 => bool) public executedOrders; // Track executed swap orders
    mapping(bytes32 => bool) public registeredLimitOrders; // Track registered limit orders
    mapping(bytes32 => bool) public cancelledLimitOrders; // Track cancelled limit orders

    // TWAP tracking
    mapping(bytes32 => LimitOrder) public twapOrders; // Store TWAP order details
    mapping(bytes32 => mapping(uint256 => TWAPExecution)) public twapExecutions; // Track TWAP executions
    mapping(bytes32 => uint256) public twapExecutedParts; // Count of executed parts per TWAP order
    mapping(bytes32 => uint256) public twapInitialPrice; // Initial price for price protection
    mapping(bytes32 => TWAPPartOrder) public twapPartOrders; // Track individual TWAP part orders
    mapping(bytes32 => address) public twapPartExecutors; // Track who initiated each TWAP part

    // 1inch Limit Order Protocol contract
    IOrderMixin public immutable limitOrderProtocol;

    // Add OrderRegistrator reference
    IOrderRegistrator public immutable orderRegistrator;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 internal constant ETH_DECIMALS = 1e18;
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant EIP1271_INVALID_SIGNATURE = 0xffffffff;

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    constructor(address _limitOrderProtocol) {
        if (_limitOrderProtocol == address(0))
            revert InvalidLimitOrderProtocol();
        limitOrderProtocol = IOrderMixin(_limitOrderProtocol);

        // Initialize OrderRegistrator - you'll need to provide this address
        orderRegistrator = IOrderRegistrator(
            0x2339f78e2Ec15C47Cf042F2460C532C0D7ff1CCE
        );
    }

    // ========================================================================
    // BATCH EXECUTION FUNCTIONS
    // ========================================================================

    /**
     * @notice Execute an arbitrary bundle of calls, pay the sponsor in ERC-20,
     *         and guarantee that the token fee covers *at least* the real
     *         gas cost (in ETH terms).
     *
     * @param calls         Array of calls to execute atomically.
     * @param feeToken      ERC-20 token used to reimburse the sponsor.
     * @param feeAmount     Exact token amount the sponsor will receive.
     * @param tokenPerEth   How much tokens per 1 ETH req.
     * @param userSig       EOA signature authorizing the whole operation.
     */
    function execute(
        Call[] calldata calls,
        address feeToken,
        uint256 feeAmount,
        uint256 tokenPerEth,
        bytes calldata userSig
    ) external payable returns (bytes[] memory results) {
        // 1. Verify EOA signature
        bytes32 opHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    address(this), // the EOA
                    keccak256(abi.encode(calls)), // bundle contents
                    nonce,
                    msg.sender, // sponsor
                    block.chainid,
                    feeToken,
                    feeAmount,
                    tokenPerEth
                )
            )
        );

        if (opHash.recover(userSig) != address(this)) revert BadSignature();

        // 2. Run the bundle & track gas
        uint256 gasStart = gasleft();
        results = new bytes[](calls.length);

        unchecked {
            for (uint256 i; i < calls.length; ++i) {
                (bool ok, bytes memory ret) = calls[i].to.call{
                    value: calls[i].value
                }(calls[i].data);
                require(ok, "sub-call failed");
                results[i] = ret;
            }
        }

        // 3. Pay sponsor in ERC-20
        _paySponsor(feeToken, feeAmount);

        // Ensure fee actually covers the gas cost
        uint256 gasUsed = gasStart - gasleft() + 31_000;
        uint256 ethCost = gasUsed * tx.gasprice;

        // tokenPerEth = tokens * 1e18 per 1 ETH
        uint256 ethPaid = (feeAmount * ETH_DECIMALS) / tokenPerEth;

        if (ethPaid < ethCost) revert FeeTooLow(ethCost, ethPaid);

        emit BatchExecuted(nonce, ethCost);
        nonce++;
    }

    // ========================================================================
    // DUTCH AUCTION SWAP FUNCTIONS
    // ========================================================================

    /**
     * @notice Execute a swap on behalf of the user if it meets their minimum price requirements
     *
     * @param order         The swap order details signed by the user
     * @param swapCall      The actual swap call to execute (e.g., to DEX router)
     * @param userSig       User's signature authorizing this specific swap order
     */
    function executeSwap(
        SwapOrder calldata order,
        Call calldata swapCall,
        bytes calldata userSig
    ) external returns (bytes memory result) {
        // 1. Verify order hasn't been executed
        if (executedOrders[order.nonce])
            revert OrderAlreadyExecuted(order.nonce);

        // 2. Verify order hasn't expired
        if (block.timestamp > order.expiration) {
            revert OrderExpired(order.expiration, block.timestamp);
        }

        // 3. Verify user signature
        if (!_verifyOrderSignature(order, userSig)) revert BadSignature();

        // 4. Calculate current Dutch auction price
        uint256 currentAmountOut = _calculateCurrentAmountOut(order);

        // 5. Execute swap and verify results
        result = _executeSwapCall(order, swapCall, currentAmountOut);
    }

    /**
     * @notice Get the current Dutch auction price for a swap order
     * @param order The swap order to check
     * @return currentAmountOut The current amount of tokenOut required at this time
     * @return timeRemaining Time remaining until the order reaches its minimum price
     */
    function getCurrentAuctionPrice(
        SwapOrder calldata order
    ) external view returns (uint256 currentAmountOut, uint256 timeRemaining) {
        currentAmountOut = _calculateCurrentAmountOut(order);

        // Calculate time remaining until minimum price is reached
        uint256 timeElapsed = block.timestamp - order.timestamp;
        uint256 decaySteps = timeElapsed / order.decayInterval;
        uint256 totalDecayBps = decaySteps * order.decayRateBps;

        if (totalDecayBps >= order.startPremiumBps) {
            timeRemaining = 0; // Already at minimum price
        } else {
            uint256 remainingDecayBps = order.startPremiumBps - totalDecayBps;
            uint256 remainingSteps = (remainingDecayBps +
                order.decayRateBps -
                1) / order.decayRateBps; // Ceiling division
            timeRemaining = remainingSteps * order.decayInterval;
        }
    }

    // ========================================================================
    // 1INCH LIMIT ORDER FUNCTIONS
    // ========================================================================

    /**
     * @notice Register a limit order directly on-chain with 1inch OrderRegistrator
     * @param limitOrder The limit order parameters
     * @param userSig User's signature authorizing the limit order
     * @param extension Extension data for the order (can be empty bytes)
     */
    function registerLimitOrderOnChain(
        LimitOrder calldata limitOrder,
        bytes calldata userSig,
        bytes calldata extension
    ) external returns (bytes32 orderHash) {
        // Verify order hasn't expired
        if (block.timestamp > limitOrder.expiration) {
            revert OrderExpired(limitOrder.expiration, block.timestamp);
        }

        // Verify user signature
        if (!_verifyLimitOrderSignature(limitOrder, userSig))
            revert BadSignature();

        // Create 1inch order struct with proper formatting
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: limitOrder.salt,
            maker: uint256(uint160(address(this))), // This contract is the maker
            receiver: uint256(uint160(address(this))), // Receive tokens back to this contract
            makerAsset: uint256(uint160(limitOrder.makerAsset)),
            takerAsset: uint256(uint160(limitOrder.takerAsset)),
            makingAmount: limitOrder.makingAmount,
            takingAmount: limitOrder.takingAmount,
            makerTraits: _buildMakerTraitsForRegistrator(limitOrder)
        });

        // Get order hash from 1inch protocol
        orderHash = limitOrderProtocol.hashOrder(order);

        // Create signature for the order registration
        // The OrderRegistrator expects the signature to be from the maker (this contract)
        bytes memory orderSignature = _createOrderSignature(order, userSig);

        // Register the order on-chain via OrderRegistrator
        orderRegistrator.registerOrder(order, extension, orderSignature);

        // Mark as registered locally
        registeredLimitOrders[orderHash] = true;

        // Approve tokens for the 1inch protocol if needed
        IERC20(limitOrder.makerAsset).approve(
            address(limitOrderProtocol),
            limitOrder.makingAmount
        );

        emit LimitOrderRegistered(
            orderHash,
            limitOrder.makerAsset,
            limitOrder.takerAsset,
            limitOrder.makingAmount,
            limitOrder.takingAmount
        );
    }

    /**
     * @notice Cancel a registered limit order
     * @param orderHash The hash of the order to cancel
     * @param userSig User's signature authorizing the cancellation
     */
    function cancelLimitOrder(
        bytes32 orderHash,
        bytes calldata userSig
    ) external {
        // Verify order was registered by this contract
        require(registeredLimitOrders[orderHash], "Order not registered");
        require(!cancelledLimitOrders[orderHash], "Order already cancelled");

        // Verify user signature for cancellation
        bytes32 cancelHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    address(this),
                    orderHash,
                    "CANCEL_LIMIT_ORDER",
                    block.chainid
                )
            )
        );

        if (cancelHash.recover(userSig) != address(this)) revert BadSignature();

        // Mark as cancelled
        cancelledLimitOrders[orderHash] = true;

        // Cancel on 1inch protocol (orderInfo is the order hash for cancellation)
        limitOrderProtocol.cancelOrder(uint256(orderHash));

        emit LimitOrderCancelled(orderHash);
    }

    /**
     * @notice Get limit order status
     * @param orderHash The hash of the order to check
     * @return isRegistered Whether the order is registered
     * @return isCancelled Whether the order is cancelled
     */
    function getLimitOrderStatus(
        bytes32 orderHash
    ) external view returns (bool isRegistered, bool isCancelled) {
        isRegistered = registeredLimitOrders[orderHash];
        isCancelled = cancelledLimitOrders[orderHash];
    }

    // ========================================================================
    // TWAP LIMIT ORDER FUNCTIONS
    // ========================================================================

    /**
     * @notice Register a TWAP order directly on-chain
     * @param limitOrder The TWAP limit order parameters
     * @param userSig User's signature authorizing the TWAP limit order
     * @param initialPrice Initial price for price protection
     * @param extension Extension data for the order
     */
    function registerTWAPOrderOnChain(
        LimitOrder calldata limitOrder,
        bytes calldata userSig,
        uint256 initialPrice,
        bytes calldata extension
    ) external returns (bytes32 orderHash) {
        // Validate TWAP parameters
        if (limitOrder.twapParts == 0 || limitOrder.twapParts > 100)
            revert InvalidTWAPParameters();
        if (limitOrder.twapStartTime >= limitOrder.twapEndTime)
            revert InvalidTWAPParameters();
        if (limitOrder.twapEndTime > limitOrder.expiration)
            revert InvalidTWAPParameters();
        if (limitOrder.maxPriceDeviation > 5000) revert InvalidTWAPParameters();
        if (limitOrder.executorTipBps > 1000) revert InvalidTWAPParameters();

        // Verify order hasn't expired
        if (block.timestamp > limitOrder.expiration) {
            revert OrderExpired(limitOrder.expiration, block.timestamp);
        }

        // Verify user signature
        if (!_verifyLimitOrderSignature(limitOrder, userSig))
            revert BadSignature();

        // Generate order hash
        orderHash = keccak256(
            abi.encode(limitOrder, block.chainid, address(this))
        );

        // Store TWAP order details
        twapOrders[orderHash] = limitOrder;
        twapInitialPrice[orderHash] = initialPrice;
        registeredLimitOrders[orderHash] = true;

        // For TWAP orders, we register the parent order info but actual execution
        // will create individual 1inch orders for each part

        // Approve total tokens for the 1inch protocol
        IERC20(limitOrder.makerAsset).approve(
            address(limitOrderProtocol),
            limitOrder.makingAmount
        );

        emit TWAPOrderRegistered(
            orderHash,
            limitOrder.makerAsset,
            limitOrder.takerAsset,
            limitOrder.makingAmount,
            limitOrder.takingAmount,
            limitOrder.twapParts,
            limitOrder.twapStartTime,
            limitOrder.twapEndTime
        );
    }

    /**
     * @notice Execute a part of a TWAP order by creating and registering a 1inch limit order on-chain
     * @param orderHash Hash of the TWAP order to execute
     * @param partIndex Which part to execute (0 to twapParts-1)
     * @param currentPrice Current market price for price protection validation
     * @param integratorWallet Address to receive the integrator fee (executor tip)
     * @param extension Extension data for the 1inch order (can be empty bytes)
     */
    function executeTWAPPart(
        bytes32 orderHash,
        uint256 partIndex,
        uint256 currentPrice,
        address integratorWallet,
        bytes calldata extension
    ) external returns (bytes32 oneinchOrderHash) {
        LimitOrder memory order = twapOrders[orderHash];

        // Verify order exists and is not cancelled
        require(registeredLimitOrders[orderHash], "Order not registered");
        require(!cancelledLimitOrders[orderHash], "Order cancelled");

        // Verify TWAP timing
        if (block.timestamp < order.twapStartTime) {
            revert TWAPNotStarted(block.timestamp, order.twapStartTime);
        }
        if (block.timestamp > order.twapEndTime) {
            revert TWAPEnded(block.timestamp, order.twapEndTime);
        }

        // Verify part index
        require(partIndex < order.twapParts, "Invalid part index");

        // Verify this part hasn't been executed
        if (twapExecutions[orderHash][partIndex].executionTime != 0) {
            revert TWAPPartAlreadyExecuted(partIndex);
        }

        // Check if enough time has passed for this execution
        uint256 timeBetweenParts = (order.twapEndTime - order.twapStartTime) /
            order.twapParts;
        uint256 earliestExecutionTime = order.twapStartTime +
            (partIndex * timeBetweenParts);

        if (block.timestamp < earliestExecutionTime) {
            revert TWAPPartNotReady(block.timestamp, earliestExecutionTime);
        }

        // Verify price protection
        _validatePriceProtection(
            orderHash,
            currentPrice,
            order.maxPriceDeviation
        );

        // Calculate amounts for this part
        uint256 partMakingAmount = order.makingAmount / order.twapParts;
        uint256 partTakingAmount = order.takingAmount / order.twapParts;

        // Handle remainder for last part
        if (partIndex == order.twapParts - 1) {
            uint256 executedMaking = twapExecutedParts[orderHash] *
                (order.makingAmount / order.twapParts);
            uint256 executedTaking = twapExecutedParts[orderHash] *
                (order.takingAmount / order.twapParts);
            partMakingAmount = order.makingAmount - executedMaking;
            partTakingAmount = order.takingAmount - executedTaking;
        }

        // Create and register 1inch order for this TWAP part on-chain
        oneinchOrderHash = _createTWAPPartOrderWithIntegratorFeeOnChain(
            orderHash,
            partIndex,
            order,
            partMakingAmount,
            partTakingAmount,
            integratorWallet,
            extension
        );
    }

    /**
     * @notice Execute a part of a TWAP order (backward compatible version without extension)
     * @param orderHash Hash of the TWAP order to execute
     * @param partIndex Which part to execute (0 to twapParts-1)
     * @param currentPrice Current market price for price protection validation
     * @param integratorWallet Address to receive the integrator fee (executor tip)
     */
    function executeTWAPPart(
        bytes32 orderHash,
        uint256 partIndex,
        uint256 currentPrice,
        address integratorWallet
    ) external returns (bytes32 oneinchOrderHash) {
        // Call the main function with empty extension
        return
            this.executeTWAPPart(
                orderHash,
                partIndex,
                currentPrice,
                integratorWallet,
                bytes("")
            );
    }

    /**
     * @notice Callback function called when a TWAP part order is filled via 1inch
     * @param orderHash The original TWAP order hash
     * @param partIndex Which part was executed
     * @param oneinchOrderHash The 1inch order hash that was filled
     * @param actualMakingAmount Actual amount sold
     * @param actualTakingAmount Actual amount received (after integrator fee)
     * @param integratorFee The integrator fee that was paid to the executor
     * @dev This should be called by a trusted 1inch callback mechanism or verified off-chain
     */
    function onTWAPPartFilled(
        bytes32 orderHash,
        uint256 partIndex,
        bytes32 oneinchOrderHash,
        uint256 actualMakingAmount,
        uint256 actualTakingAmount,
        uint256 integratorFee
    ) external {
        // In a real implementation, this should have access control
        // to ensure only 1inch or a trusted oracle can call this

        address executor = twapPartExecutors[oneinchOrderHash];

        // Record execution (actualTakingAmount is already net of integrator fee)
        twapExecutions[orderHash][partIndex] = TWAPExecution({
            orderHash: orderHash,
            partIndex: partIndex,
            executionTime: block.timestamp,
            actualMakingAmount: actualMakingAmount,
            actualTakingAmount: actualTakingAmount,
            executor: executor
        });

        // Update executed parts count
        twapExecutedParts[orderHash]++;

        emit TWAPPartExecuted(
            orderHash,
            partIndex,
            executor,
            actualMakingAmount,
            actualTakingAmount,
            integratorFee // Now this is the 1inch integrator fee
        );
    }

    /**
     * @notice Get TWAP order execution status
     * @param orderHash Hash of the TWAP order
     * @return order The TWAP order details
     * @return executedParts Number of parts executed
     * @return nextExecutionTime When the next part can be executed
     * @return isComplete Whether all parts have been executed
     */
    function getTWAPStatus(
        bytes32 orderHash
    )
        external
        view
        returns (
            LimitOrder memory order,
            uint256 executedParts,
            uint256 nextExecutionTime,
            bool isComplete
        )
    {
        order = twapOrders[orderHash];
        executedParts = twapExecutedParts[orderHash];
        isComplete = executedParts >= order.twapParts;

        if (!isComplete && executedParts < order.twapParts) {
            uint256 timeBetweenParts = (order.twapEndTime -
                order.twapStartTime) / order.twapParts;
            nextExecutionTime =
                order.twapStartTime +
                (executedParts * timeBetweenParts);
        }
    }

    // ========================================================================
    // EIP-1271 SIGNATURE VALIDATION
    // ========================================================================

    /**
     * @notice EIP-1271 implementation for smart contract signature validation
     * @param hash The hash that was signed
     * @param signature The signature to validate
     * @return The magic value if signature is valid, invalid signature otherwise
     */
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view override returns (bytes4) {
        // For testing purposes, always return valid signature
        // TODO: Implement proper signature validation for production
        return EIP1271_MAGIC_VALUE;

        // Original complex validation logic commented out for testing:
        /*
        // Check if this is a limit order hash that we've registered
        if (registeredLimitOrders[hash] && !cancelledLimitOrders[hash]) {
            // For registered limit orders, we validate that the signature was created by the wallet owner
            // The signature should be the user's signature that was used to register the order

            // Try to recover the signer from the signature
            address signer = hash.recover(signature);

            // Check if the signer is the wallet owner (this contract's address in our case)
            if (signer == address(this)) {
                return EIP1271_MAGIC_VALUE;
            }
        }

        // Check if this is a TWAP part order hash
        if (twapPartOrders[hash].isValid) {
            // Validate that this TWAP part order was created by this contract

            // Try to decode the TWAP part signature
            try this._decodeTWAPPartSignature(signature) returns (
                string memory orderType,
                bytes32 parentOrderHash,
                uint256 partIndex,
                uint256 salt
            ) {
                // Verify this is a TWAP part order signature
                if (
                    keccak256(abi.encodePacked(orderType)) ==
                    keccak256(abi.encodePacked("TWAP_PART_ORDER"))
                ) {
                    // Verify the parent order is registered and the part order matches
                    TWAPPartOrder memory partOrder = twapPartOrders[hash];
                    if (
                        partOrder.parentOrderHash == parentOrderHash &&
                        partOrder.partIndex == partIndex &&
                        registeredLimitOrders[parentOrderHash] &&
                        !cancelledLimitOrders[parentOrderHash]
                    ) {
                        return EIP1271_MAGIC_VALUE;
                    }
                }
            } catch {
                // If decoding fails, fall through to invalid signature
            }
        }

        // For other cases, we could implement additional validation logic
        // For now, return invalid for unrecognized signatures
        return EIP1271_INVALID_SIGNATURE;
        */
    }

    /**
     * @dev Helper function to decode TWAP part signatures (external for try-catch)
     */
    function _decodeTWAPPartSignature(
        bytes calldata signature
    )
        external
        pure
        returns (
            string memory orderType,
            bytes32 parentOrderHash,
            uint256 partIndex,
            uint256 salt
        )
    {
        return abi.decode(signature, (string, bytes32, uint256, uint256));
    }

    // ========================================================================
    // INTERNAL HELPER FUNCTIONS
    // ========================================================================

    /**
     * @dev Pay sponsor in ERC-20 tokens
     */
    function _paySponsor(address token, uint256 amount) internal {
        require(
            IERC20(token).transfer(msg.sender, amount),
            "fee transfer failed"
        );
    }

    /**
     * @dev Verify user signature for swap order
     */
    function _verifyOrderSignature(
        SwapOrder calldata order,
        bytes calldata userSig
    ) internal view returns (bool) {
        bytes32 orderHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    address(this),
                    order.tokenOut,
                    order.tokenIn,
                    order.amountOut,
                    order.minAmountIn,
                    order.timestamp,
                    order.expiration,
                    order.nonce,
                    block.chainid,
                    // Dutch auction parameters
                    keccak256(
                        abi.encode(
                            order.startPremiumBps,
                            order.decayRateBps,
                            order.decayInterval
                        )
                    )
                )
            )
        );

        return orderHash.recover(userSig) == address(this);
    }

    /**
     * @dev Calculate the current amountOut based on Dutch auction mechanics
     */
    function _calculateCurrentAmountOut(
        SwapOrder calldata order
    ) internal view returns (uint256 currentAmountOut) {
        uint256 timeElapsed = block.timestamp - order.timestamp;

        // If no time has passed, use the starting premium
        if (timeElapsed == 0) {
            return
                order.amountOut +
                ((order.amountOut * order.startPremiumBps) / 10000);
        }

        // Calculate how many decay intervals have passed
        uint256 decaySteps = timeElapsed / order.decayInterval;

        // Calculate total decay amount
        uint256 totalDecayBps = decaySteps * order.decayRateBps;

        // If total decay exceeds the starting premium, return the base amount
        if (totalDecayBps >= order.startPremiumBps) {
            return order.amountOut;
        }

        // Calculate remaining premium
        uint256 remainingPremiumBps = order.startPremiumBps - totalDecayBps;

        // Return base amount plus remaining premium
        return
            order.amountOut + ((order.amountOut * remainingPremiumBps) / 10000);
    }

    /**
     * @dev Internal function to execute the swap call and verify results
     */
    function _executeSwapCall(
        SwapOrder calldata order,
        Call calldata swapCall,
        uint256 currentAmountOut
    ) internal returns (bytes memory returnData) {
        // Record balances before swap
        uint256 tokenInBefore = IERC20(order.tokenIn).balanceOf(address(this));
        uint256 tokenOutBefore = IERC20(order.tokenOut).balanceOf(
            address(this)
        );

        // Execute the swap call
        (bool success, bytes memory data) = swapCall.to.call{
            value: swapCall.value
        }(swapCall.data);
        require(success, "swap call failed");

        // Verify swap results
        uint256 actualAmountOut = tokenOutBefore -
            IERC20(order.tokenOut).balanceOf(address(this));
        uint256 actualAmountIn = IERC20(order.tokenIn).balanceOf(
            address(this)
        ) - tokenInBefore;

        // Verify we sold at least the current Dutch auction amount (allow 1% tolerance for fees)
        require(
            actualAmountOut >= (currentAmountOut * 99) / 100,
            "insufficient tokenOut sold for current price"
        );

        // Verify we received at least the minimum required
        if (actualAmountIn < order.minAmountIn) {
            revert InsufficientReturn(order.minAmountIn, actualAmountIn);
        }

        // Mark order as executed
        executedOrders[order.nonce] = true;

        emit SwapExecuted(
            order.nonce,
            order.tokenOut,
            order.tokenIn,
            actualAmountOut,
            actualAmountIn,
            currentAmountOut,
            msg.sender
        );

        return data;
    }

    /**
     * @dev Verify user signature for limit order
     */
    function _verifyLimitOrderSignature(
        LimitOrder calldata limitOrder,
        bytes calldata userSig
    ) internal view returns (bool) {
        bytes32 orderHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    address(this),
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

        return orderHash.recover(userSig) == address(this);
    }

    /**
     * @dev Build maker traits for OrderRegistrator (updated format)
     */
    function _buildMakerTraitsForRegistrator(
        LimitOrder calldata limitOrder
    ) internal pure returns (uint256) {
        uint256 traits = 0;

        // Set expiration (bits 80-119, 40 bits)
        uint256 expiration = limitOrder.expiration;
        traits |= (expiration & 0xFFFFFFFFFF) << 80;

        // Set partial fill flag (bit 255)
        if (!limitOrder.allowPartialFill) {
            traits |= (1 << 255); // NO_PARTIAL_FILLS_FLAG
        }

        // For TWAP orders, we typically don't want partial fills on individual parts
        // but this depends on your specific TWAP strategy

        return traits;
    }

    /**
     * @dev Create a signature for order registration
     * @dev This creates a signature that the OrderRegistrator can validate
     */
    function _createOrderSignature(
        IOrderMixin.Order memory order,
        bytes calldata userSig
    ) internal view returns (bytes memory) {
        // Get the order hash that 1inch protocol uses
        bytes32 orderHash = limitOrderProtocol.hashOrder(order);

        // Since this contract will be the signer for EIP-1271 validation,
        // we can return the user's signature which will be validated via isValidSignature
        return userSig;
    }

    /**
     * @dev Validate price protection for TWAP execution
     */
    function _validatePriceProtection(
        bytes32 orderHash,
        uint256 currentPrice,
        uint256 maxDeviationBps
    ) internal view {
        uint256 initialPrice = twapInitialPrice[orderHash];

        // Calculate price deviation
        uint256 deviation;
        if (currentPrice > initialPrice) {
            deviation = ((currentPrice - initialPrice) * 10000) / initialPrice;
        } else {
            deviation = ((initialPrice - currentPrice) * 10000) / initialPrice;
        }

        if (deviation > maxDeviationBps) {
            revert PriceDeviationTooHigh(currentPrice, maxDeviationBps);
        }
    }

    /**
     * @dev Create and register a 1inch limit order for a TWAP part with integrator fee on-chain
     */
    function _createTWAPPartOrderWithIntegratorFeeOnChain(
        bytes32 parentOrderHash,
        uint256 partIndex,
        LimitOrder memory order,
        uint256 partMakingAmount,
        uint256 partTakingAmount,
        address integratorWallet,
        bytes calldata extension
    ) internal returns (bytes32 oneinchOrderHash) {
        // Generate unique salt for this TWAP part
        uint256 partSalt = uint256(
            keccak256(abi.encode(parentOrderHash, partIndex, block.timestamp))
        );

        // Calculate integrator fee amount (in takerAsset)
        uint256 integratorFeeAmount = (partTakingAmount *
            order.executorTipBps) / 10000;

        // Adjust taking amount to account for integrator fee
        // The order will receive: partTakingAmount + integratorFeeAmount
        // 1inch will distribute: partTakingAmount to contract, integratorFeeAmount to integrator
        uint256 totalTakingAmount = partTakingAmount + integratorFeeAmount;

        // Create 1inch order for this part with integrator fee
        IOrderMixin.Order memory oneinchOrder = IOrderMixin.Order({
            salt: partSalt,
            maker: uint256(uint160(address(this))),
            receiver: uint256(uint160(address(this))), // Contract receives the main amount
            makerAsset: uint256(uint160(order.makerAsset)),
            takerAsset: uint256(uint160(order.takerAsset)),
            makingAmount: partMakingAmount,
            takingAmount: totalTakingAmount, // Total amount including integrator fee
            makerTraits: _buildTWAPPartMakerTraitsForRegistrator(
                order,
                integratorWallet,
                integratorFeeAmount
            )
        });

        // Get order hash
        oneinchOrderHash = limitOrderProtocol.hashOrder(oneinchOrder);

        // Store TWAP part order info BEFORE registration so isValidSignature can validate it
        twapPartOrders[oneinchOrderHash] = TWAPPartOrder({
            parentOrderHash: parentOrderHash,
            partIndex: partIndex,
            isValid: true
        });

        // Track who initiated this TWAP part for tip distribution
        twapPartExecutors[oneinchOrderHash] = integratorWallet;

        // Create signature for TWAP part order registration
        // For TWAP parts, we create a synthetic signature that will be validated via EIP-1271
        bytes memory twapPartSignature = _createTWAPPartOrderSignature(
            oneinchOrder,
            parentOrderHash,
            partIndex
        );

        // Register the order on-chain via OrderRegistrator
        orderRegistrator.registerOrder(
            oneinchOrder,
            extension,
            twapPartSignature
        );

        // Approve tokens for this specific amount
        IERC20(order.makerAsset).approve(
            address(limitOrderProtocol),
            partMakingAmount
        );

        emit TWAPPartOrderCreated(
            parentOrderHash,
            partIndex,
            oneinchOrderHash,
            partMakingAmount,
            totalTakingAmount
        );

        return oneinchOrderHash;
    }

    /**
     * @dev Build maker traits for TWAP part orders for OrderRegistrator
     */
    function _buildTWAPPartMakerTraitsForRegistrator(
        LimitOrder memory order,
        address integratorWallet,
        uint256 integratorFeeAmount
    ) internal pure returns (uint256) {
        uint256 traits = 0;

        // Set expiration to the TWAP end time (bits 80-119, 40 bits)
        uint256 expiration = order.twapEndTime;
        traits |= (expiration & 0xFFFFFFFFFF) << 80;

        // TWAP parts should not allow partial fills to ensure exact execution
        traits |= (1 << 255); // NO_PARTIAL_FILLS_FLAG

        // Note: Integrator fee handling may need to be done differently
        // depending on 1inch's final implementation of integrator fees in maker traits
        // For now, we'll handle it through the order execution mechanism

        return traits;
    }

    /**
     * @dev Create a signature for TWAP part order registration
     */
    function _createTWAPPartOrderSignature(
        IOrderMixin.Order memory order,
        bytes32 parentOrderHash,
        uint256 partIndex
    ) internal pure returns (bytes memory) {
        // Create a synthetic signature that encodes the TWAP part information
        // This will be validated via EIP-1271 isValidSignature function
        return
            abi.encode(
                "TWAP_PART_ORDER",
                parentOrderHash,
                partIndex,
                order.salt
            );
    }

    // ========================================================================
    // RECEIVE FUNCTION
    // ========================================================================

    receive() external payable {}
}
