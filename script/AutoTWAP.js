const { ethers } = require("ethers");
const axios = require("axios");

// Configuration
const RPC_URL = "https://mainnet.optimism.io";
const PRIVATE_KEY = process.env.EXECUTOR_PK; // Bot's private key
const CONTRACT_ADDRESS = "0xa11ceB73aB7888736F264A3502933178f0a18553"; // User's delegated wallet
// !PLACEHOLDER! - Order hash removed for security
// Load from environment variable instead:
// const ORDER_HASH = process.env.TWAP_ORDER_HASH;
const ORDER_HASH =
  process.env.TWAP_ORDER_HASH ||
  "0x0000000000000000000000000000000000000000000000000000000000000000";

// Setup provider and contract
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// DelegatedWallet ABI (just the functions we need)
const contractABI = [
  "function getTWAPStatus(bytes32 orderHash) view returns (tuple(address makerAsset, address takerAsset, uint256 makingAmount, uint256 takingAmount, uint256 salt, uint256 expiration, bool allowPartialFill, uint256 twapStartTime, uint256 twapEndTime, uint256 twapParts, uint256 maxPriceDeviation, uint256 executorTipBps) order, uint256 executedParts, uint256 nextExecutionTime, bool isComplete)",
  "function executeTWAPPart(bytes32 orderHash, uint256 partIndex, uint256 currentPrice, address integratorWallet) returns (bytes32)",
];

const contract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, wallet);

class TWAPBot {
  constructor() {
    this.isRunning = false;
    this.checkInterval = 60000; // Check every minute
  }

  async start() {
    console.log("🤖 Starting TWAP Bot...");
    this.isRunning = true;

    while (this.isRunning) {
      try {
        await this.checkAndExecuteTWAP();
        await this.sleep(this.checkInterval);
      } catch (error) {
        console.error("❌ Bot error:", error.message);
        await this.sleep(5000); // Wait 5s on error
      }
    }
  }

  async checkAndExecuteTWAP() {
    console.log(`⏰ Checking TWAP status at ${new Date().toISOString()}`);

    // Get TWAP status
    const [order, executedParts, nextExecutionTime, isComplete] =
      await contract.getTWAPStatus(ORDER_HASH);

    console.log({
      totalParts: order.twapParts,
      executedParts: executedParts.toString(),
      nextExecutionTime: nextExecutionTime.toString(),
      currentTime: Math.floor(Date.now() / 1000),
      isComplete,
    });

    // Check if TWAP is complete
    if (isComplete) {
      console.log("✅ TWAP execution complete!");
      this.stop();
      return;
    }

    // Check if it's time to execute next part
    const currentTime = Math.floor(Date.now() / 1000);
    if (currentTime >= nextExecutionTime) {
      await this.executeTWAPPart(executedParts, order);
    } else {
      const waitTime = nextExecutionTime - currentTime;
      console.log(`⏳ Next execution in ${waitTime} seconds`);
    }
  }

  async executeTWAPPart(partIndex, order) {
    try {
      console.log(`🚀 Executing TWAP part ${partIndex}...`);

      // Calculate current price (in production, get from oracle/DEX)
      const currentPrice =
        (order.takingAmount * BigInt(1e18)) / order.makingAmount;

      // Execute TWAP part with EIP-7702 delegation
      const tx = await contract.executeTWAPPart(
        ORDER_HASH,
        partIndex,
        currentPrice,
        wallet.address // We get the integrator tip!
      );

      console.log(`📋 Transaction sent: ${tx.hash}`);
      const receipt = await tx.wait();
      console.log(
        `✅ Part ${partIndex} executed in block ${receipt.blockNumber}`
      );

      // Extract the 1inch order hash from events
      const oneinchOrderHash = this.extractOrderHash(receipt);
      if (oneinchOrderHash) {
        await this.submit1inchOrder(oneinchOrderHash, order, partIndex);
      }
    } catch (error) {
      console.error(`❌ Failed to execute part ${partIndex}:`, error.message);
    }
  }

  extractOrderHash(receipt) {
    // Look for TWAPPartOrderCreated event
    for (const log of receipt.logs) {
      try {
        // This would need the actual event signature
        // For demo, we'll return a mock hash
        return "0x" + Math.random().toString(16).slice(2).padStart(64, "0");
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  async submit1inchOrder(oneinchOrderHash, order, partIndex) {
    try {
      console.log(`📤 Submitting part ${partIndex} to 1inch API...`);

      const partAmount = order.makingAmount / order.twapParts;
      const partTaking = order.takingAmount / order.twapParts;

      const orderData = {
        orderHash: oneinchOrderHash,
        signature: await this.getEIP1271Signature(oneinchOrderHash),
        data: {
          salt: Math.floor(Math.random() * 1000000).toString(),
          maker: CONTRACT_ADDRESS,
          receiver: CONTRACT_ADDRESS,
          makerAsset: order.makerAsset,
          takerAsset: order.takerAsset,
          makingAmount: partAmount.toString(),
          takingAmount: partTaking.toString(),
          makerTraits: "0x0", // Simplified
        },
      };

      const response = await axios.post(
        `https://api.1inch.dev/orderbook/v4.0/10/order`,
        orderData,
        {
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer YOUR_1INCH_API_KEY",
          },
        }
      );

      console.log(`✅ Part ${partIndex} submitted to 1inch orderbook`);
    } catch (error) {
      console.error(`❌ Failed to submit to 1inch:`, error.message);
    }
  }

  async getEIP1271Signature(orderHash) {
    // In production, this would call the contract's isValidSignature
    // For demo, return mock signature
    return "0x1234567890abcdef".padEnd(132, "0");
  }

  stop() {
    console.log("🛑 Stopping TWAP Bot...");
    this.isRunning = false;
  }

  sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

// Usage
async function main() {
  const bot = new TWAPBot();

  // Handle graceful shutdown
  process.on("SIGINT", () => {
    console.log("\n📡 Received shutdown signal...");
    bot.stop();
    process.exit(0);
  });

  await bot.start();
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = { TWAPBot };
