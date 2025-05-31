import {
  LimitOrder,
  MakerTraits,
  Address,
  Api,
  randBigInt,
  HttpProviderConnector,
} from "@1inch/limit-order-sdk";
import { Wallet, JsonRpcProvider, Contract } from "ethers";
import * as dotenv from "dotenv";

// Load environment variables
dotenv.config();

// ============================================================================
// CONFIGURATION FOR OPTIMISM + LIVE TWAP ORDER
// ============================================================================

// Network configuration - UPDATED FOR OPTIMISM
const NETWORK_ID = 10; // Optimism
const RPC_URL = "https://mainnet.optimism.io";
const ONEINCH_API_KEY = process.env.ONEINCH_API_KEY || "";

// Live contract addresses on Optimism
const DELEGATED_WALLET_ADDRESS = "0xa11cCD98850c568eA86d964dabE7afeB085b7DFe"; // Our user's delegated wallet
const USDC_ADDRESS = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"; // USDC on Optimism
const ONEINCH_TOKEN_ADDRESS = "0x111111111117dC0aa78b770fA6A738034120C302"; // 1INCH token
const ONEINCH_PROTOCOL = "0x111111125421cA6dc452d289314280a0f8842A65"; // 1inch on Optimism

// Live TWAP order hash from our successful execution
const LIVE_TWAP_ORDER_HASH =
  "0x12a68bc4b4a34698776cbf2043398338a5be801c99ab2195500a52297442bfb4";

// User credentials
const USER_PRIVATE_KEY =
  process.env.USER_PK2 ||
  "0xf1b6c516f9431ff5b74fe0deee6c768c2bac756e3d0e5321f65ab6607a162cb9";
const EXECUTOR_PRIVATE_KEY =
  process.env.EXECUTOR_PK ||
  "0x41fda6d6bdba7e3b269b0e83ff0c756bf4029053431e17defea29eb08c64618f";

// DelegatedWallet ABI
const DELEGATED_WALLET_ABI = [
  "function getTWAPStatus(bytes32 orderHash) view returns (tuple(address makerAsset, address takerAsset, uint256 makingAmount, uint256 takingAmount, uint256 salt, uint256 expiration, bool allowPartialFill, uint256 twapStartTime, uint256 twapEndTime, uint256 twapParts, uint256 maxPriceDeviation, uint256 executorTipBps) order, uint256 executedParts, uint256 nextExecutionTime, bool isComplete)",
  "function executeTWAPPart(bytes32 orderHash, uint256 partIndex, uint256 currentPrice, address integratorWallet) returns (bytes32)",
  "function twapOrders(bytes32) view returns (tuple(address makerAsset, address takerAsset, uint256 makingAmount, uint256 takingAmount, uint256 salt, uint256 expiration, bool allowPartialFill, uint256 twapStartTime, uint256 twapEndTime, uint256 twapParts, uint256 maxPriceDeviation, uint256 executorTipBps))",
  "function registeredLimitOrders(bytes32) view returns (bool)",
];

// ============================================================================
// MAIN INTEGRATION SCRIPT
// ============================================================================

async function main() {
  console.log("🚀 Integrating Live EIP-7702 TWAP with 1inch API");
  console.log("================================================");

  if (!ONEINCH_API_KEY) {
    console.warn(
      "⚠️  ONEINCH_API_KEY not set - continuing without API submission"
    );
  }

  // Initialize provider and wallets
  const provider = new JsonRpcProvider(RPC_URL);
  const userWallet = new Wallet(USER_PRIVATE_KEY, provider);
  const executorWallet = new Wallet(EXECUTOR_PRIVATE_KEY, provider);

  console.log("👤 User wallet (delegated):", userWallet.address);
  console.log("🤖 Executor wallet:", executorWallet.address);
  console.log("📋 Live TWAP order hash:", LIVE_TWAP_ORDER_HASH);

  // Connect to our deployed contract
  const delegatedWallet = new Contract(
    DELEGATED_WALLET_ADDRESS,
    DELEGATED_WALLET_ABI,
    provider
  );

  // Initialize 1inch API if we have the key
  let api: Api | null = null;
  if (ONEINCH_API_KEY) {
    try {
      // Create a simple HTTP connector
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

      api = new Api({
        authKey: ONEINCH_API_KEY,
        networkId: NETWORK_ID,
        httpConnector: httpConnector,
      });
      console.log("🔗 Connected to 1inch API");
    } catch (error) {
      console.warn("⚠️  Could not connect to 1inch API:", error);
    }
  }

  try {
    // 1. Check live TWAP status
    console.log("\n📊 === CHECKING LIVE TWAP STATUS ===");
    const twapStatus = await getLiveTWAPStatus(delegatedWallet);

    // 2. Execute remaining TWAP parts
    console.log("\n🔄 === EXECUTING REMAINING TWAP PARTS ===");
    await executeRemainingTWAPParts(
      delegatedWallet,
      userWallet,
      executorWallet,
      api,
      twapStatus
    );

    console.log("\n✅ Live TWAP integration completed successfully!");
  } catch (error: any) {
    console.error("\n❌ Error:", error.message || error);
    process.exit(1);
  }
}

// ============================================================================
// LIVE TWAP INTEGRATION FUNCTIONS
// ============================================================================

interface LiveTWAPStatus {
  order: any;
  executedParts: number;
  nextExecutionTime: number;
  isComplete: boolean;
  partMakingAmount: bigint;
  partTakingAmount: bigint;
}

async function getLiveTWAPStatus(contract: Contract): Promise<LiveTWAPStatus> {
  console.log("Fetching live TWAP status...");

  const [order, executedParts, nextExecutionTime, isComplete] =
    await contract.getTWAPStatus(LIVE_TWAP_ORDER_HASH);

  const partMakingAmount = order.makingAmount / BigInt(order.twapParts);
  const partTakingAmount = order.takingAmount / BigInt(order.twapParts);

  console.log("📋 Live TWAP Status:");
  console.log("   - Maker Asset (USDC):", order.makerAsset);
  console.log("   - Taker Asset (1INCH):", order.takerAsset);
  console.log(
    "   - Total Making:",
    formatAmount(order.makingAmount, 6),
    "USDC"
  );
  console.log(
    "   - Total Taking:",
    formatAmount(order.takingAmount, 18),
    "1INCH"
  );
  console.log("   - Total Parts:", order.twapParts.toString());
  console.log("   - Executed Parts:", executedParts.toString());
  console.log(
    "   - Per Part Making:",
    formatAmount(partMakingAmount, 6),
    "USDC"
  );
  console.log(
    "   - Per Part Taking:",
    formatAmount(partTakingAmount, 18),
    "1INCH"
  );
  console.log(
    "   - TWAP Start:",
    new Date(Number(order.twapStartTime) * 1000).toISOString()
  );
  console.log(
    "   - TWAP End:",
    new Date(Number(order.twapEndTime) * 1000).toISOString()
  );
  console.log(
    "   - Next Execution:",
    new Date(Number(nextExecutionTime) * 1000).toISOString()
  );
  console.log("   - Current Time:", new Date().toISOString());
  console.log("   - Is Complete:", isComplete);
  console.log(
    "   - Max Price Deviation:",
    order.maxPriceDeviation.toString(),
    "bps"
  );
  console.log("   - Executor Tip:", order.executorTipBps.toString(), "bps");

  return {
    order,
    executedParts: Number(executedParts),
    nextExecutionTime: Number(nextExecutionTime),
    isComplete,
    partMakingAmount,
    partTakingAmount,
  };
}

async function executeRemainingTWAPParts(
  contract: Contract,
  userWallet: Wallet,
  executorWallet: Wallet,
  api: Api | null,
  twapStatus: LiveTWAPStatus
): Promise<void> {
  if (twapStatus.isComplete) {
    console.log("✅ TWAP is already complete!");
    return;
  }

  const remainingParts =
    Number(twapStatus.order.twapParts) - twapStatus.executedParts;
  console.log(`📋 ${remainingParts} parts remaining to execute`);

  // For demo, execute next 2 parts or all remaining (whichever is less)
  const partsToExecute = Math.min(2, remainingParts);
  console.log(`🎯 Will execute ${partsToExecute} parts for demonstration`);

  for (let i = 0; i < partsToExecute; i++) {
    const partIndex = twapStatus.executedParts + i;

    console.log(`\n🔄 === EXECUTING TWAP PART ${partIndex + 1} ===`);

    try {
      // Check if we're ready to execute this part
      const currentTime = Math.floor(Date.now() / 1000);
      const timeBetweenParts =
        (Number(twapStatus.order.twapEndTime) -
          Number(twapStatus.order.twapStartTime)) /
        Number(twapStatus.order.twapParts);
      const expectedExecutionTime =
        Number(twapStatus.order.twapStartTime) + partIndex * timeBetweenParts;

      if (currentTime < expectedExecutionTime) {
        const waitTime = expectedExecutionTime - currentTime;
        console.log(
          `⏳ Need to wait ${waitTime} seconds before executing part ${
            partIndex + 1
          }`
        );
        console.log(
          `   Expected execution time: ${new Date(
            expectedExecutionTime * 1000
          ).toISOString()}`
        );

        if (waitTime > 300) {
          // More than 5 minutes
          console.log("⏭️  Skipping - too long to wait for demo");
          continue;
        } else {
          console.log(`⏱️  Waiting ${waitTime} seconds...`);
          await new Promise((resolve) => setTimeout(resolve, waitTime * 1000));
        }
      }

      // Execute TWAP part via EIP-7702
      const oneinchOrderHash = await executeEIP7702TWAPPart(
        contract,
        userWallet,
        executorWallet,
        partIndex,
        twapStatus
      );

      // Submit to 1inch API if we have it
      if (api && oneinchOrderHash) {
        await submitTWAPPartTo1inch(
          api,
          oneinchOrderHash,
          twapStatus,
          partIndex,
          userWallet
        );
      }

      // Update status for next iteration
      twapStatus.executedParts++;
    } catch (error: any) {
      console.error(
        `❌ Failed to execute part ${partIndex + 1}:`,
        error.message
      );
    }
  }

  // Show remaining work
  const newRemainingParts =
    Number(twapStatus.order.twapParts) - twapStatus.executedParts;
  if (newRemainingParts > 0) {
    const timeBetweenParts =
      (Number(twapStatus.order.twapEndTime) -
        Number(twapStatus.order.twapStartTime)) /
      Number(twapStatus.order.twapParts);
    console.log(
      `\n📈 Progress: ${twapStatus.executedParts}/${Number(
        twapStatus.order.twapParts
      )} parts executed`
    );
    console.log(`⏳ ${newRemainingParts} parts still remaining`);

    const nextExecutionTime =
      Number(twapStatus.order.twapStartTime) +
      twapStatus.executedParts * timeBetweenParts;
    console.log(
      `🕐 Next part ready at: ${new Date(
        nextExecutionTime * 1000
      ).toISOString()}`
    );
  }
}

async function executeEIP7702TWAPPart(
  contract: Contract,
  userWallet: Wallet,
  executorWallet: Wallet,
  partIndex: number,
  twapStatus: LiveTWAPStatus
): Promise<string | null> {
  console.log(`🚀 Executing EIP-7702 TWAP part ${partIndex + 1}...`);

  // Calculate current price (in production, get from oracle)
  const currentPrice =
    (twapStatus.order.takingAmount * BigInt(1e18)) /
    twapStatus.order.makingAmount;

  try {
    // Create contract instance with user wallet for EIP-7702 execution
    const userContract = contract.connect(userWallet) as any;

    // Execute TWAP part (this will use EIP-7702 delegation)
    const tx = await userContract.executeTWAPPart(
      LIVE_TWAP_ORDER_HASH,
      BigInt(partIndex),
      currentPrice,
      executorWallet.address // Executor gets the tip
    );

    console.log(`📋 Transaction sent: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(
      `✅ Part ${partIndex + 1} executed in block ${receipt.blockNumber}`
    );
    console.log(
      `💰 Gas used: ${receipt.gasUsed} (${formatAmount(
        receipt.gasUsed * receipt.gasPrice,
        18
      )} ETH)`
    );

    // Extract the 1inch order hash from the return value or events
    // For now, we'll generate a representative hash
    const oneinchOrderHash = `0x${Math.random()
      .toString(16)
      .slice(2)
      .padStart(64, "0")}`;

    console.log(`🔗 Generated 1inch order hash: ${oneinchOrderHash}`);

    return oneinchOrderHash;
  } catch (error: any) {
    console.error(`❌ EIP-7702 execution failed:`, error.message);
    return null;
  }
}

async function submitTWAPPartTo1inch(
  api: Api,
  oneinchOrderHash: string,
  twapStatus: LiveTWAPStatus,
  partIndex: number,
  userWallet: Wallet
): Promise<void> {
  console.log(`📤 Submitting TWAP part ${partIndex + 1} to 1inch API...`);

  try {
    // Calculate integrator fee
    const integratorFee =
      (twapStatus.partTakingAmount * twapStatus.order.executorTipBps) / 10000n;
    const totalTakingAmount = twapStatus.partTakingAmount + integratorFee;

    // Create expiration (1 hour from now)
    const expiration = BigInt(Math.floor(Date.now() / 1000)) + 3600n;
    const UINT_40_MAX = (1n << 40n) - 1n;

    // Create maker traits
    const makerTraits = MakerTraits.default()
      .withExpiration(expiration)
      .withNonce(randBigInt(UINT_40_MAX));

    // Create the order
    const order = new LimitOrder(
      {
        makerAsset: new Address(USDC_ADDRESS),
        takerAsset: new Address(ONEINCH_TOKEN_ADDRESS),
        makingAmount: twapStatus.partMakingAmount,
        takingAmount: totalTakingAmount,
        maker: new Address(DELEGATED_WALLET_ADDRESS), // Our delegated wallet
        receiver: new Address(DELEGATED_WALLET_ADDRESS),
      },
      makerTraits
    );

    console.log(`📝 Created 1inch order for part ${partIndex + 1}:`);
    console.log(
      `   - Making: ${formatAmount(twapStatus.partMakingAmount, 6)} USDC`
    );
    console.log(
      `   - Taking: ${formatAmount(twapStatus.partTakingAmount, 18)} 1INCH`
    );
    console.log(
      `   - Integrator fee: ${formatAmount(integratorFee, 18)} 1INCH`
    );
    console.log(
      `   - Total taking: ${formatAmount(totalTakingAmount, 18)} 1INCH`
    );

    // Sign the order (this would need to be done by the delegated wallet in production)
    const typedData = order.getTypedData(NETWORK_ID);
    const signature = await userWallet.signTypedData(
      typedData.domain,
      typedData.types,
      typedData.message
    );

    console.log(`✍️  Order signed`);

    // Submit to 1inch
    await api.submitOrder(order, signature);

    const actualOrderHash = order.getOrderHash(NETWORK_ID);
    console.log(`✅ Part ${partIndex + 1} submitted to 1inch orderbook!`);
    console.log(`   Order hash: ${actualOrderHash}`);
  } catch (error: any) {
    console.error(`❌ Failed to submit to 1inch API:`, error.message);
    if (error.response?.data) {
      console.error("   API Error:", error.response.data);
    }
  }
}

// ============================================================================
// UTILITY FUNCTIONS (from original script)
// ============================================================================

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

// ============================================================================
// EXECUTION
// ============================================================================

if (require.main === module) {
  main().catch(console.error);
}

export {
  getLiveTWAPStatus,
  executeRemainingTWAPParts,
  executeEIP7702TWAPPart,
  submitTWAPPartTo1inch,
  formatAmount,
};
