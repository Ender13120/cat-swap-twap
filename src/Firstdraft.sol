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

    /* ========== EVENTS & ERRORS ======================================== */
    event BatchExecuted(uint256 indexed nonce, uint256 gasUsedWei);
    error BadSignature();
    error FeeTooLow(uint256 ethCost, uint256 ethPaid);

    /* ========== STORAGE ================================================= */
    uint256 public nonce;

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

    /* ========== INTERNAL HELPERS ====================================== */
    function _paySponsor(address token, uint256 amount) internal {
        require(
            IERC20(token).transfer(msg.sender, amount),
            "fee transfer failed"
        );
    }

    receive() external payable {}
}
