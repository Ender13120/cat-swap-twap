// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Firstdraft.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Execute7702 is Script {
    /* ──────────────────────────────────────────────────────────────
       CONFIG – adjust these constants as needed
    ────────────────────────────────────────────────────────────── */
    address constant FEE_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address constant RECIPIENT = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik
    uint256 constant TRANSFER_AMOUNT = 500000; // 0.5 USDC
    uint256 constant FEE_AMOUNT = 1000000; // 1 USDC
    uint256 constant TOKEN_PER_ETH = 3000e6; // 3000 USDC per ETH

    // Our deployed DelegatedWallet implementation
    address constant IMPLEMENTATION_ADDRESS =
        0x53F93d13Cb9A315c19d24bCbc570E38c506E23c2;

    // Our fixed addresses and keys
    address constant user = 0xa11ceB73aB7888736F264A3502933178f0a18553;
    address constant sponsor = 0xb0b4240FDD73c460736c2f65b385647f2425C68f;
    // !PLACEHOLDER! - Private keys removed for security
    // Load from environment variables instead:
    // uint256 userPk = vm.envUint("USER_PK");
    // uint256 sponsorPk = vm.envUint("SPONSOR_PK");

    function run() external {
        // Load private keys from environment
        uint256 userPk = vm.envUint("USER_PK");
        uint256 sponsorPk = vm.envUint("SPONSOR_PK");

        console.log("=== Execute7702 Script ===");
        console.log("User:", user);
        console.log("Sponsor:", sponsor);
        console.log("Implementation:", IMPLEMENTATION_ADDRESS);

        // Check balances
        uint256 usdcBalance = IERC20(FEE_TOKEN).balanceOf(user);
        console.log("User USDC balance:", usdcBalance);

        // -----------------------------------------------------------------
        // 1. build batch: transfer tokens to recipient
        DelegatedWallet.Call[] memory calls = new DelegatedWallet.Call[](1);
        calls[0] = DelegatedWallet.Call({
            to: FEE_TOKEN,
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                RECIPIENT,
                TRANSFER_AMOUNT
            )
        });

        // -----------------------------------------------------------------
        // 2. Fetch current nonce from the contract (optional - more accurate)
        uint256 currentNonce = 0; // Start with 0 for first transaction
        // If you want to fetch the nonce from the contract instead of assuming 0:
        // DelegatedWallet walletContract = DelegatedWallet(user);
        // currentNonce = walletContract.nonce();

        console.log("Using nonce:", currentNonce);

        // -----------------------------------------------------------------
        // 3. user signs operation hash
        bytes32 opHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user, // wallet address
                    keccak256(abi.encode(calls)),
                    currentNonce, // Current nonce
                    sponsor, // relayer
                    block.chainid,
                    FEE_TOKEN,
                    FEE_AMOUNT,
                    TOKEN_PER_ETH
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, opHash);
        bytes memory userSig = abi.encodePacked(r, s, v);

        console.log("Operation hash generated and signed");

        // -----------------------------------------------------------------
        // 4. sponsor sends transaction with delegation
        vm.startBroadcast(sponsorPk);

        // Attach delegation to user
        vm.signAndAttachDelegation(IMPLEMENTATION_ADDRESS, userPk);

        // Execute the call
        bytes memory data = abi.encodeWithSelector(
            DelegatedWallet.execute.selector,
            calls,
            FEE_TOKEN,
            FEE_AMOUNT,
            TOKEN_PER_ETH,
            userSig
        );

        (bool ok, bytes memory result) = user.call(data);

        if (ok) {
            console.log("[SUCCESS] EIP-7702 execution completed!");
            console.log(
                "   - Transferred",
                TRANSFER_AMOUNT,
                "USDC to recipient"
            );
            console.log("   - Paid", FEE_AMOUNT, "USDC fee to sponsor");
        } else {
            console.log("[FAILED] Delegated execution failed");
            if (result.length > 0) {
                console.log("Error data length:", result.length);
            }
        }

        require(ok, "delegated execution failed");

        vm.stopBroadcast();
    }
}
