// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DelegatedWallet {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

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

    /* ========== EVENTS & ERRORS ======================================== */
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

    error BadSignature();
    error FeeTooLow(uint256 ethCost, uint256 ethPaid);
    error OrderExpired(uint256 expiration, uint256 currentTime);
    error InsufficientReturn(uint256 minAmountIn, uint256 actualAmountIn);
    error OrderAlreadyExecuted(uint256 orderNonce);

    /* ========== STORAGE ================================================= */
    uint256 public nonce;
    mapping(uint256 => bool) public executedOrders; // Track executed swap orders

    /* ========== CONSTANTS ============================================== */
    uint256 internal constant ETH_DECIMALS = 1e18;

    /* ========== PUBLIC EXECUTOR ======================================== */
    /**
     * @notice Execute an arbitrary bundle of calls, pay the sponsor in ERC-20,
     *         and guarantee that the token fee covers *at least* the real
     *         gas cost (in ETH terms).
     *
     * @param calls         Array of calls to execute atomically.
     * @param feeToken      ERC-20 token used to reimburse the sponsor.
     * @param feeAmount     Exact token amount the sponsor will receive.
     * @param tokenPerEth   How much tokens per 1 ETH req.
     *
     * @param userSig       EOA signature authorizing the whole operation.
     */
    function execute(
        Call[] calldata calls,
        address feeToken,
        uint256 feeAmount,
        uint256 tokenPerEth,
        bytes calldata userSig
    ) external payable returns (bytes[] memory results) {
        /* ---------- 1. Verify EOA signature ---------------------------- */
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

        /* ---------- 2. Run the bundle & track gas ---------------------- */
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

    // -- ONCHAIN SWAP FUNCTIONS  --
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
        /* ---------- 1. Verify order hasn't been executed --------------- */
        if (executedOrders[order.nonce])
            revert OrderAlreadyExecuted(order.nonce);

        /* ---------- 2. Verify order hasn't expired --------------------- */
        if (block.timestamp > order.expiration) {
            revert OrderExpired(order.expiration, block.timestamp);
        }

        /* ---------- 3. Verify user signature --------------------------- */
        if (!_verifyOrderSignature(order, userSig)) revert BadSignature();

        /* ---------- 4. Calculate current Dutch auction price ----------- */
        uint256 currentAmountOut = _calculateCurrentAmountOut(order);

        /* ---------- 5. Execute swap and verify results ----------------- */
        result = _executeSwapCall(order, swapCall, currentAmountOut);
    }

    /**
     * @dev Verify the user's signature for a swap order
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
     * @param order The swap order with Dutch auction parameters
     * @return currentAmountOut The current amount to sell based on time elapsed
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

    /* ========== INTERNAL HELPERS ====================================== */
    function _paySponsor(address token, uint256 amount) internal {
        require(
            IERC20(token).transfer(msg.sender, amount),
            "fee transfer failed"
        );
    }

    receive() external payable {}
}
