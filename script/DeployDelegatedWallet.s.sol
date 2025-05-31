// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DelegatedWallet} from "../src/Firstdraft.sol";

contract DeployDelegatedWalletScript is Script {
    /* ──────────────────────────────────────────────────────────────
       CONFIGURATION
    ────────────────────────────────────────────────────────────── */

    // 1inch Limit Order Protocol addresses per network
    address constant ETHEREUM_LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;
    address constant POLYGON_LIMIT_ORDER_PROTOCOL =
        0x94Bc2a1C732BcAd7343B25af48385Fe76E08734f;
    address constant BSC_LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;
    address constant ARBITRUM_LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;
    address constant OPTIMISM_LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;
    address constant AVALANCHE_LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;

    function run() external returns (DelegatedWallet wallet) {
        uint256 deployerPrivateKey = vm.envUint("SPONSOR_PK");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DelegatedWallet Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        // Get the appropriate 1inch protocol address for this chain
        address limitOrderProtocol = _getLimitOrderProtocolAddress();
        console.log("1inch Limit Order Protocol:", limitOrderProtocol);

        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");

        if (balance < 0.001 ether) {
            console.log(
                "WARNING: Low deployer balance. Consider adding more ETH for gas."
            );
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the DelegatedWallet contract
        console.log("\nDeploying DelegatedWallet...");
        wallet = new DelegatedWallet(limitOrderProtocol);

        vm.stopBroadcast();

        console.log("\n=== Deployment Successful ===");
        console.log("DelegatedWallet deployed at:", address(wallet));
        console.log("Implementation address:", address(wallet));
        console.log(
            "Constructor parameter (1inch protocol):",
            limitOrderProtocol
        );

        // Verify the deployment
        _verifyDeployment(wallet, limitOrderProtocol);

        // Log usage instructions
        _logUsageInstructions(address(wallet));

        return wallet;
    }

    function _getLimitOrderProtocolAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            // Ethereum Mainnet
            return ETHEREUM_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 137) {
            // Polygon
            return POLYGON_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 56) {
            // BSC
            return BSC_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 42161) {
            // Arbitrum One
            return ARBITRUM_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 10) {
            // Optimism
            return OPTIMISM_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 43114) {
            // Avalanche
            return AVALANCHE_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 5) {
            // Goerli testnet (use mainnet address)
            return ETHEREUM_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 11155111) {
            // Sepolia testnet (use mainnet address)
            return ETHEREUM_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 80001) {
            // Mumbai testnet (use Polygon address)
            return POLYGON_LIMIT_ORDER_PROTOCOL;
        } else if (chainId == 31337) {
            // Local development (use mainnet address)
            console.log(
                "WARNING: Using mainnet 1inch address for local development"
            );
            return ETHEREUM_LIMIT_ORDER_PROTOCOL;
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "Unsupported chain ID: ",
                        vm.toString(chainId)
                    )
                )
            );
        }
    }

    function _verifyDeployment(
        DelegatedWallet wallet,
        address expectedProtocol
    ) internal view {
        console.log("\n=== Deployment Verification ===");

        // Check that the contract was deployed correctly
        require(address(wallet).code.length > 0, "Contract not deployed");
        console.log("Contract has bytecode");

        // Check that the limit order protocol is set correctly
        address actualProtocol = address(wallet.limitOrderProtocol());
        require(
            actualProtocol == expectedProtocol,
            "Incorrect limit order protocol"
        );
        console.log("Limit order protocol correctly set");

        // Check initial state
        uint256 initialNonce = wallet.nonce();
        require(initialNonce == 0, "Initial nonce should be 0");
        console.log("Initial nonce is 0");

        console.log("All deployment checks passed");
    }

    function _logUsageInstructions(address walletAddress) internal view {
        console.log("\n=== Usage Instructions ===");
        console.log("1. Update your .env file with:");
        console.log("   DELEGATED_WALLET_ADDRESS=", walletAddress);

        console.log("\n2. Update Send7702.s.sol implementation address:");
        console.log("   IMPLEMENTATION_ADDRESS =", walletAddress);

        console.log("\n3. To use with EIP-7702:");
        console.log("   - Set USER_PK2 in .env (EOA that will delegate)");
        console.log("   - Set SPONSOR_PK in .env (pays gas & broadcasts)");
        console.log("   - Run: forge script script/Send7702.s.sol --broadcast");

        console.log("\n4. For 1inch integration:");
        console.log(
            "   - Update scripts/submit-1inch-orders.ts with new address"
        );
        console.log("   - Set ONEINCH_API_KEY in .env");
        console.log("   - Run: npm run 1inch-orders");

        console.log("\n5. Contract functions available:");
        console.log("   - execute(): Batch operations with fee payment");
        console.log("   - executeSwap(): Dutch auction swaps");
        console.log("   - registerLimitOrder(): 1inch limit orders");
        console.log("   - registerTWAPOrder(): TWAP limit orders");
        console.log("   - executeTWAPPart(): Execute TWAP parts");

        console.log("\n=== Next Steps ===");
        console.log("- Fund the deployed contract with tokens for testing");
        console.log("- Ensure EOAs have ETH for gas");
        console.log("- Test with small amounts first (1 USDC as configured)");
    }
}
