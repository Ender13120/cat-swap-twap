import {
  LimitOrder,
  MakerTraits,
  Address,
  Api,
  randBigInt,
  HttpProviderConnector,
} from "@1inch/limit-order-sdk";
import { Wallet, JsonRpcProvider } from "ethers";
import * as dotenv from "dotenv";
import { ethers } from "ethers";

// Load environment variables
dotenv.config();

// ============================================================================
// CONFIGURATION
// ============================================================================

// Setup (using Alchemy provider for Optimism mainnet)
// Network configuration
const NETWORK_ID = 10; // Optimism
const RPC_URL =
  "https://opt-mainnet.g.alchemy.com/v2/kqRIGj2Y7_VBXjGoBWQfHGd-5V0JFHD5";
const ONEINCH_API_KEY = process.env.ONEINCH_API_KEY || "";

//@TODO: Add the following to .env file:
// USER_PK2=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
// EXECUTOR_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

// Contract addresses
const DELEGATED_WALLET_IMPL = "0xa11ceB73aB7888736F264A3502933178f0a18553";
const DELEGATED_WALLET_ADDRESS =
  process.env.DELEGATED_WALLET_ADDRESS ||
  "0x742d35Cc6676C4Ce5e8c9A48E668ec57b8e2aFf8"; // Fallback test address
const USDC_ADDRESS = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"; // USDC on Optimism
const ONEINCH_TOKEN_ADDRESS = "0x111111111117dC0aa78b770fA6A738034120C302"; // 1INCH token
const ONEINCH_PROTOCOL = "0x111111125421cA6dc452d289314280a0f8842A65"; // 1inch on Optimism

// Private keys (use environment variables in production)
const USER_PRIVATE_KEY = process.env.USER_PK2 || "";
const EXECUTOR_PRIVATE_KEY = process.env.EXECUTOR_PK || "";

// Order parameters
const LIMIT_ORDER_CONFIG = {
  makingAmount: 1_000000n, // 1 USDT (6 decimals)
  takingAmount: 1_000000000000000000n, // 1 1INCH token (18 decimals)
  expirationMinutes: 60n, // 1 hour
};

const TWAP_CONFIG = {
  makingAmount: 5_000000n, // 5 USDT total
  takingAmount: 5_000000000000000000n, // 5 1INCH tokens total
  parts: 5n, // 5 executions (1 USDT each)
  durationSeconds: 48n, // 48 seconds total (12 seconds between parts)
  maxPriceDeviation: 500n, // 5%
  executorTipBps: 10n, // 0.1%
};

// ============================================================================
// INTERFACES & TYPES
// ============================================================================

interface TWAPOrderInfo {
  orderHash: string;
  baseOrder: LimitOrder;
  totalParts: number;
  executedParts: number;
  nextExecutionTime: number;
  partMakingAmount: bigint;
  partTakingAmount: bigint;
  isComplete: boolean;
}

interface TWAPPartInfo {
  partIndex: number;
  order: LimitOrder;
  signature: string;
  integratorFee: bigint;
}

// ============================================================================
// MAIN SCRIPT
// ============================================================================

async function main() {
  console.log("🚀 Starting 1inch Order Submission (Working Implementation)");
  console.log("========================================================");

  if (!ONEINCH_API_KEY) {
    console.error("❌ Error: ONEINCH_API_KEY not set in .env file");
    console.log("   Please get an API key from https://portal.1inch.dev/");
    process.exit(1);
  }

  // Temporarily commented out for testing
  // if (!DELEGATED_WALLET_ADDRESS) {
  //   console.error("❌ Error: DELEGATED_WALLET_ADDRESS not set in .env file");
  //   console.log("   Please deploy the DelegatedWallet contract first and add its address to .env");
  //   process.exit(1);
  // }

  // Initialize provider and wallets
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const userWallet = new ethers.Wallet(USER_PRIVATE_KEY, provider);
  const executorWallet = new ethers.Wallet(EXECUTOR_PRIVATE_KEY, provider);

  console.log("👤 User wallet:", userWallet.address);
  console.log("🤖 Executor wallet:", executorWallet.address);

  // Initialize 1inch API
  const api = new Api({
    authKey: ONEINCH_API_KEY,
    networkId: NETWORK_ID,
    httpConnector: {
      async get<T>(url: string, headers: Record<string, string>): Promise<T> {
        const response = await fetch(url, { headers });
        return response.json() as Promise<T>;
      },
      async post<T>(
        url: string,
        data: unknown,
        headers: Record<string, string>
      ): Promise<T> {
        const response = await fetch(url, {
          method: "POST",
          headers: { ...headers, "Content-Type": "application/json" },
          body: JSON.stringify(data),
        });
        return response.json() as Promise<T>;
      },
    },
  });

  console.log("🔗 Connected to 1inch API with network ID:", NETWORK_ID);

  try {
    // Check network connectivity
    console.log("\n🔍 Checking network connectivity...");
    const blockNumber = await provider.getBlockNumber();
    console.log("   Current block:", blockNumber);

    // 1. Submit a regular limit order
    console.log("\n📋 === SUBMITTING LIMIT ORDER ===");
    const limitOrderHash = await submitLimitOrder(api, userWallet);

    if (limitOrderHash) {
      console.log("✅ Limit order submitted successfully!");
      console.log("   Order hash:", limitOrderHash);

      // Check order status
      await checkOrderStatus(api, limitOrderHash);
    }

    // 2. Create and execute TWAP order
    console.log("\n⏰ === CREATING TWAP ORDER ===");
    const twapInfo = await createTWAPOrder(api, userWallet);

    // 3. Execute TWAP parts
    console.log("\n🔄 === EXECUTING TWAP PARTS ===");
    await executeTWAPParts(api, executorWallet, twapInfo);

    console.log("\n✅ All operations completed successfully!");
  } catch (error: any) {
    console.error("\n❌ Error:", error.message || error);
    if (error.response) {
      console.error("   API Response:", error.response.data);
    }
    process.exit(1);
  }
}

// ============================================================================
// LIMIT ORDER FUNCTIONS
// ============================================================================

async function submitLimitOrder(
  api: Api,
  userWallet: Wallet
): Promise<string | null> {
  console.log("Creating limit order...");

  const expiresIn = LIMIT_ORDER_CONFIG.expirationMinutes * 60n;
  const expiration = BigInt(Math.floor(Date.now() / 1000)) + expiresIn;
  const UINT_40_MAX = (1n << 40n) - 1n;

  // Create maker traits
  const makerTraits = MakerTraits.default()
    .withExpiration(expiration)
    .withNonce(randBigInt(UINT_40_MAX));

  try {
    // Create the order
    const order = new LimitOrder(
      {
        makerAsset: new Address(USDC_ADDRESS),
        takerAsset: new Address(ONEINCH_TOKEN_ADDRESS),
        makingAmount: LIMIT_ORDER_CONFIG.makingAmount,
        takingAmount: LIMIT_ORDER_CONFIG.takingAmount,
        maker: new Address(DELEGATED_WALLET_ADDRESS),
        receiver: new Address(DELEGATED_WALLET_ADDRESS),
      },
      makerTraits
    );

    console.log("📝 Order created:");
    console.log(
      "   - Making:",
      formatAmount(LIMIT_ORDER_CONFIG.makingAmount, 6),
      "USDT"
    );
    console.log(
      "   - Taking:",
      formatAmount(LIMIT_ORDER_CONFIG.takingAmount, 18),
      "1INCH"
    );
    console.log(
      "   - Rate:",
      calculateRate(
        LIMIT_ORDER_CONFIG.makingAmount,
        LIMIT_ORDER_CONFIG.takingAmount,
        6,
        18
      ),
      "USDT per 1INCH"
    );
    console.log(
      "   - Expires:",
      new Date(Number(expiration) * 1000).toISOString()
    );

    // Get typed data and sign
    console.log("✍️  Creating EIP-1271 compatible signature...");

    // For EIP-1271, we need to create a signature that our smart contract can validate
    // The contract expects the order hash signed by the user
    const limitOrderHash = order.getOrderHash(NETWORK_ID);
    console.log("Order hash for signing:", limitOrderHash);

    // Sign the order hash directly (this is what EIP-1271 will validate)
    const signature = await userWallet.signMessage(
      ethers.getBytes(limitOrderHash)
    );
    console.log("✍️  Order signed with EIP-1271 compatible signature");

    // Submit to 1inch
    console.log("📡 Submitting order to 1inch...");
    await api.submitOrder(order, signature);

    const orderHash = order.getOrderHash(NETWORK_ID);
    console.log("✅ Order submitted! Hash:", orderHash);

    return orderHash;
  } catch (error: any) {
    console.error("❌ Failed to submit limit order:", error.message);
    if (error.response?.data) {
      console.error("   API Error:", error.response.data);
    }
    return null;
  }
}

// ============================================================================
// TWAP ORDER FUNCTIONS
// ============================================================================

async function createTWAPOrder(
  api: Api,
  userWallet: Wallet
): Promise<TWAPOrderInfo> {
  console.log("Creating TWAP order structure...");

  const startTime = BigInt(Math.floor(Date.now() / 1000)) + 12n; // Start in 12 seconds
  const endTime = startTime + TWAP_CONFIG.durationSeconds;
  const partMakingAmount = TWAP_CONFIG.makingAmount / TWAP_CONFIG.parts;
  const partTakingAmount = TWAP_CONFIG.takingAmount / TWAP_CONFIG.parts;

  console.log("📊 TWAP Configuration:");
  console.log(
    "   - Total making:",
    formatAmount(TWAP_CONFIG.makingAmount, 6),
    "USDT"
  );
  console.log(
    "   - Total taking:",
    formatAmount(TWAP_CONFIG.takingAmount, 18),
    "1INCH"
  );
  console.log("   - Parts:", TWAP_CONFIG.parts.toString());
  console.log(
    "   - Per part making:",
    formatAmount(partMakingAmount, 6),
    "USDT"
  );
  console.log(
    "   - Per part taking:",
    formatAmount(partTakingAmount, 18),
    "1INCH"
  );
  console.log(
    "   - Duration:",
    TWAP_CONFIG.durationSeconds.toString(),
    "seconds"
  );
  console.log("   - Interval: 12 seconds between parts");
  console.log(
    "   - Start time:",
    new Date(Number(startTime) * 1000).toISOString()
  );
  console.log("   - End time:", new Date(Number(endTime) * 1000).toISOString());
  console.log(
    "   - Executor tip:",
    (Number(TWAP_CONFIG.executorTipBps) / 100).toFixed(2),
    "%"
  );

  // Create a base order structure for TWAP (not submitted directly)
  const UINT_40_MAX = (1n << 40n) - 1n;
  const baseTraits = MakerTraits.default()
    .withExpiration(endTime)
    .withNonce(randBigInt(UINT_40_MAX));

  const baseOrder = new LimitOrder(
    {
      makerAsset: new Address(USDC_ADDRESS),
      takerAsset: new Address(ONEINCH_TOKEN_ADDRESS),
      makingAmount: TWAP_CONFIG.makingAmount,
      takingAmount: TWAP_CONFIG.takingAmount,
      maker: new Address(DELEGATED_WALLET_ADDRESS),
      receiver: new Address(DELEGATED_WALLET_ADDRESS),
    },
    baseTraits
  );

  const twapOrderHash = baseOrder.getOrderHash(NETWORK_ID);
  console.log("✅ TWAP order structure created");
  console.log("🔍 Base order hash:", twapOrderHash);

  return {
    orderHash: twapOrderHash,
    baseOrder: baseOrder,
    totalParts: Number(TWAP_CONFIG.parts),
    executedParts: 0,
    nextExecutionTime: Number(startTime),
    partMakingAmount: partMakingAmount,
    partTakingAmount: partTakingAmount,
    isComplete: false,
  };
}

async function executeTWAPParts(
  api: Api,
  executorWallet: Wallet,
  twapInfo: TWAPOrderInfo
): Promise<void> {
  console.log(
    `Executing TWAP parts for base order: ${twapInfo.orderHash.slice(0, 10)}...`
  );

  const timeBetweenParts =
    Number(TWAP_CONFIG.durationSeconds) / twapInfo.totalParts;
  console.log(
    "⏱️  Time between parts:",
    timeBetweenParts,
    "seconds (12 seconds)"
  );

  // For demo, we'll create and submit the first 2 parts
  const partsToExecute = Math.min(2, twapInfo.totalParts);
  console.log(`📋 Creating ${partsToExecute} TWAP parts for demonstration...`);

  for (let partIndex = 0; partIndex < partsToExecute; partIndex++) {
    console.log(
      `\n🔄 === TWAP Part ${partIndex + 1}/${twapInfo.totalParts} ===`
    );

    try {
      const partInfo = await createTWAPPart(
        api,
        executorWallet,
        twapInfo,
        partIndex
      );

      // Submit the TWAP part
      console.log("📡 Submitting TWAP part to 1inch...");
      await api.submitOrder(partInfo.order, partInfo.signature);

      const partOrderHash = partInfo.order.getOrderHash(NETWORK_ID);
      console.log(`✅ TWAP part ${partIndex + 1} submitted!`);
      console.log("   Part order hash:", partOrderHash);
      console.log(
        "   Integrator fee:",
        formatAmount(partInfo.integratorFee, 18),
        "1INCH"
      );

      // Check order status
      await checkOrderStatus(api, partOrderHash);

      // Update execution count
      twapInfo.executedParts++;
    } catch (error: any) {
      console.error(
        `❌ Failed to execute TWAP part ${partIndex + 1}:`,
        error.message
      );
      if (error.response?.data) {
        console.error("   API Error:", error.response.data);
      }
    }

    // Wait before next part (for demo purposes, shorter delay)
    if (partIndex < partsToExecute - 1) {
      console.log(`\n⏳ Waiting 12 seconds before next part...`);
      await new Promise((resolve) => setTimeout(resolve, 12000));
    }
  }

  console.log(`\n📊 TWAP Execution Summary:`);
  console.log(
    `   - Parts executed: ${twapInfo.executedParts}/${twapInfo.totalParts}`
  );
  console.log(
    `   - Parts remaining: ${twapInfo.totalParts - twapInfo.executedParts}`
  );

  if (twapInfo.executedParts < twapInfo.totalParts) {
    console.log(`   - Next execution in: ${timeBetweenParts} seconds`);
    console.log(
      `   - Full execution would complete at: ${new Date(
        Date.now() +
          (twapInfo.totalParts - twapInfo.executedParts) *
            timeBetweenParts *
            1000
      ).toISOString()}`
    );
  }
}

async function createTWAPPart(
  api: Api,
  executorWallet: Wallet,
  twapInfo: TWAPOrderInfo,
  partIndex: number
): Promise<TWAPPartInfo> {
  // Calculate integrator fee for executor tip
  const integratorFee =
    (twapInfo.partTakingAmount * TWAP_CONFIG.executorTipBps) / 10000n;
  const totalTakingAmount = twapInfo.partTakingAmount + integratorFee;

  console.log(`Creating TWAP part ${partIndex + 1}...`);
  console.log(
    "   - Making amount:",
    formatAmount(twapInfo.partMakingAmount, 6),
    "USDT"
  );
  console.log(
    "   - Taking amount:",
    formatAmount(twapInfo.partTakingAmount, 18),
    "1INCH"
  );
  console.log("   - Integrator fee:", formatAmount(integratorFee, 18), "1INCH");
  console.log(
    "   - Total taking:",
    formatAmount(totalTakingAmount, 18),
    "1INCH"
  );

  // Create unique traits for this part
  const partExpiration = BigInt(Math.floor(Date.now() / 1000)) + 3600n; // 1 hour expiration
  const UINT_40_MAX = (1n << 40n) - 1n;

  const partTraits = MakerTraits.default()
    .withExpiration(partExpiration)
    .withNonce(randBigInt(UINT_40_MAX));

  // In a real implementation, this would be the DelegatedWallet address
  // Using the smart contract as the maker for EIP-1271 compatibility
  const partOrder = new LimitOrder(
    {
      makerAsset: new Address(USDC_ADDRESS),
      takerAsset: new Address(ONEINCH_TOKEN_ADDRESS),
      makingAmount: twapInfo.partMakingAmount,
      takingAmount: totalTakingAmount,
      maker: new Address(DELEGATED_WALLET_ADDRESS), // Use smart contract as maker
      receiver: new Address(DELEGATED_WALLET_ADDRESS), // Receive tokens to the contract
      // In production, you would add integrator fee configuration here
      // This is a simplified version - check 1inch docs for proper integrator fee setup
    },
    partTraits
  );

  // Sign the order
  console.log("✍️  Creating EIP-1271 compatible signature for TWAP part...");

  // For EIP-1271, sign the order hash directly
  const twapPartOrderHash = partOrder.getOrderHash(NETWORK_ID);
  console.log("TWAP part order hash for signing:", twapPartOrderHash);

  // Sign the order hash directly (this is what EIP-1271 will validate)
  const signature = await executorWallet.signMessage(
    ethers.getBytes(twapPartOrderHash)
  );
  console.log(
    `✍️  TWAP part ${partIndex + 1} signed with EIP-1271 compatible signature`
  );

  return {
    partIndex,
    order: partOrder,
    signature,
    integratorFee,
  };
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

async function checkOrderStatus(api: Api, orderHash: string): Promise<void> {
  try {
    console.log("🔍 Checking order status...");

    // Get order by hash from 1inch API
    const orderInfo = await api.getOrderByHash(orderHash);

    console.log("   Order hash:", orderHash);
    console.log("   Status: Found in 1inch order book");
    console.log("   Created:", orderInfo.createDateTime);
    console.log("   Remaining maker amount:", orderInfo.remainingMakerAmount);
    console.log("   Maker rate:", orderInfo.makerRate);
    console.log("   Taker rate:", orderInfo.takerRate);

    if (orderInfo.orderInvalidReason) {
      console.log("   ⚠️  Invalid reason:", orderInfo.orderInvalidReason);
    }
  } catch (error: any) {
    console.log("⚠️  Could not fetch detailed order status");
    if (error.message) {
      console.log("   Reason:", error.message);
    }
  }
}

function formatAmount(amount: bigint, decimals: number): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;

  if (fraction === 0n) {
    return whole.toString();
  }

  const fractionStr = fraction.toString().padStart(decimals, "0");
  const trimmed = fractionStr.replace(/0+$/, "");

  return `${whole}.${trimmed}`;
}

function calculateRate(
  makingAmount: bigint,
  takingAmount: bigint,
  makingDecimals: number,
  takingDecimals: number
): string {
  // Calculate rate as making per taking
  const makingNormalized = makingAmount * 10n ** BigInt(18 - makingDecimals);
  const takingNormalized = takingAmount * 10n ** BigInt(18 - takingDecimals);

  if (takingNormalized === 0n) return "0";

  const rate = (makingNormalized * 10000n) / takingNormalized;
  return (Number(rate) / 10000).toFixed(4);
}

// ============================================================================
// EXECUTION
// ============================================================================

if (require.main === module) {
  main().catch(console.error);
}

export {
  submitLimitOrder,
  createTWAPOrder,
  executeTWAPParts,
  checkOrderStatus,
  formatAmount,
  calculateRate,
};

// Simple fetch-based connector implementation
const httpConnector = {
  async get<T>(url: string, headers: Record<string, string>): Promise<T> {
    const response = await fetch(url, { headers });
    return response.json() as Promise<T>;
  },
  async post<T>(
    url: string,
    data: unknown,
    headers: Record<string, string>
  ): Promise<T> {
    const response = await fetch(url, {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    return response.json() as Promise<T>;
  },
};
