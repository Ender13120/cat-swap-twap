# Cat Swap TWAP - Smart Contracts

A Solidity smart contract project for delegated wallet functionality with TWAP (Time-Weighted Average Price) features, Dutch auction swaps, and 1inch Limit Order Protocol integration.

## Project Structure

```
cat-swap-twap/
├── src/                    # Smart contracts source code
│   └── Firstdraft.sol     # DelegatedWallet contract
├── test/                  # Test files
├── script/                # Deployment scripts
├── lib/                   # Dependencies
│   ├── forge-std/         # Foundry standard library
│   ├── openzeppelin-contracts/  # OpenZeppelin contracts
│   └── limit-order-protocol/    # 1inch Limit Order Protocol
├── out/                   # Compiled contracts (build artifacts)
├── foundry.toml          # Foundry configuration
└── README.md             # This file
```

## Features

The `DelegatedWallet` contract provides:

### Core Features

- **Batch Execution**: Execute multiple calls atomically
- **ERC-20 Fee Payment**: Pay transaction fees in any ERC-20 token
- **Gas Cost Verification**: Ensures fee covers actual gas costs
- **Signature Verification**: EOA signature authorization for operations
- **Nonce Protection**: Prevents replay attacks

### Dutch Auction Swaps

- **Dynamic Pricing**: Prices start high and decay over time
- **Configurable Decay**: Set custom decay rates and intervals
- **Price Protection**: Ensures minimum return requirements
- **Time-based Execution**: Optimal execution timing

### 1inch Limit Order Integration

- **Limit Orders**: Create limit orders on the 1inch protocol
- **EIP-1271 Support**: Smart contract signature validation
- **Order Management**: Register, cancel, and track limit orders
- **Partial Fills**: Support for partial order execution
- **Gas Efficient**: Leverages 1inch's optimized protocol

### TWAP Limit Orders 🆕

The user requested the most complex feature: TWAP (Time-Weighted Average Price) limit orders where users sign once but anyone can execute successive orders over time with executor tips **using 1inch's native integrator fee mechanism**.

**Enhanced Data Structures:**

- Extended `LimitOrder` struct with TWAP parameters:
  - `twapStartTime`/`twapEndTime`: Execution window
  - `twapParts`: Number of separate executions (1-100)
  - `maxPriceDeviation`: Price protection in basis points
  - `executorTipBps`: Tip for executors in basis points (handled via 1inch integrator fees)
- Added `TWAPExecution` struct to track individual executions
- Added `TWAPPartOrder` struct to track 1inch order relationships
- Added comprehensive storage mappings for TWAP order tracking

**Core TWAP Functions:**

- `registerTWAPOrder()`: Register TWAP order with single user signature and initial price
- `executeTWAPPart()`: Execute individual TWAP parts with integrator fee (callable by anyone)
- `getTWAPStatus()`: Check execution progress and timing
- `onTWAPPartFilled()`: Callback when 1inch fills a TWAP part order
- `_validatePriceProtection()`: Ensure price stays within deviation limits
- `_createTWAPPartOrderWithIntegratorFee()`: Create 1inch orders with automatic tip distribution

**Key Features:**

- **Sign Once, Execute Many**: Users sign comprehensive order once for all future executions
- **1inch Integrator Fees**: Executor tips handled natively by 1inch protocol
- **Time-based Scheduling**: Parts executable at calculated intervals over duration
- **Price Protection**: Execution halts if price deviates beyond specified limits
- **Automatic Tip Distribution**: 1inch automatically pays executors via integrator fees
- **Gas Efficient**: No manual token transfers for tips
- **Remainder Handling**: Final execution gets any remaining tokens
- **Comprehensive Validation**: Timing, price, and execution state checks

**Example TWAP Order with Integrator Fees:**

- Sell 1000 USDC for ETH over 4 hours in 10 parts
- 5% maximum price deviation protection
- 0.1% executor tip per execution (paid via 1inch integrator fees)
- Parts executable every 24 minutes

### 1inch Integrator Fee Integration 💰

Our TWAP implementation leverages [1inch's native integrator fee mechanism](https://github.com/1inch/limit-order-sdk/blob/master/src/limit-order/README.md#gear-getintegratorfee) for executor tip distribution:

**Benefits:**

- **Gas Efficient**: No manual token transfers for tips
- **Automatic Distribution**: 1inch handles fee distribution natively
- **Transparent**: Fees are clearly visible in 1inch's system
- **Reliable**: Uses battle-tested 1inch infrastructure

**How It Works:**

1. **TWAP Part Creation**: When `executeTWAPPart()` is called, it creates a 1inch order with integrator fee
2. **Fee Calculation**: Executor tip is calculated as `(takingAmount * executorTipBps) / 10000`
3. **Order Submission**: Order is submitted to 1inch with integrator wallet specified
4. **Automatic Payment**: 1inch automatically pays the integrator fee to the executor
5. **Callback**: `onTWAPPartFilled()` records the execution with fee details

**Integration Example:**

```typescript
// Execute TWAP part with integrator fee
const tx = await delegatedWallet.executeTWAPPart(
  twapOrderHash,
  partIndex,
  currentPrice,
  executorWallet // This wallet will receive the integrator fee
);

// 1inch will automatically:
// 1. Fill the order
// 2. Pay the main amount to the contract
// 3. Pay the integrator fee to executorWallet
// 4. Trigger the callback with fee details
```

## Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolkit

## Installation

1. Clone the repository:

```bash
git clone <your-repo-url>
cd cat-swap-twap
```

2. Install dependencies:

```bash
forge install
```

## Usage

### Compile Contracts

```bash
forge build
```

### Run Tests

```bash
forge test
```

### Deploy

```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

## Contract Overview

### DelegatedWallet

The main contract that allows:

#### 1. Batch Execution (`execute`)

- Executing arbitrary function calls in batches
- Paying sponsors in ERC-20 tokens for gas costs
- Verifying that token payments cover actual ETH gas costs
- Using cryptographic signatures for authorization

#### 2. Dutch Auction Swaps (`executeSwap`)

- Time-weighted average price execution
- Configurable starting premium and decay rates
- Automatic price reduction over time
- Minimum return guarantees

#### 3. 1inch Limit Orders

- **`registerLimitOrder`**: Register a limit order with 1inch protocol
- **`cancelLimitOrder`**: Cancel a registered limit order
- **`getLimitOrderStatus`**: Check order status
- **`isValidSignature`**: EIP-1271 signature validation

#### 4. TWAP Limit Orders 🆕

- **`registerTWAPOrder`**: Register a TWAP order with single signature
- **`executeTWAPPart`**: Execute individual parts of TWAP order (anyone can call)
- **`getTWAPStatus`**: Check TWAP execution progress and timing

### Key Functions

#### Dutch Auction Functions

- `executeSwap()`: Execute a swap with Dutch auction pricing
- `getCurrentAuctionPrice()`: Get current auction price and time remaining
- `_calculateCurrentAmountOut()`: Calculate current Dutch auction price

#### 1inch Integration Functions

- `registerLimitOrder()`: Register a new limit order
- `cancelLimitOrder()`: Cancel an existing limit order
- `getLimitOrderStatus()`: Check if order is registered/cancelled
- `isValidSignature()`: EIP-1271 signature validation for smart contracts

#### TWAP Functions 🆕

- `registerTWAPOrder()`: Register a TWAP order with comprehensive parameters
- `executeTWAPPart()`: Execute a specific part of a TWAP order
- `getTWAPStatus()`: Get execution status and next execution time
- `_validatePriceProtection()`: Ensure price stays within deviation limits
- `_executeTWAPSwap()`: Internal function to handle TWAP part execution

## TWAP Limit Orders Deep Dive

### How TWAP Orders Work

1. **User Signs Once**: User creates and signs a TWAP order with all parameters
2. **Order Registration**: Order is registered on-chain with timing and price protection
3. **Distributed Execution**: Anyone can execute parts of the order over time
4. **Executor Rewards**: Executors receive tips for their service
5. **Price Protection**: Execution halts if price deviates too much from initial price

### TWAP Parameters

```solidity
struct LimitOrder {
    // Standard limit order fields
    address makerAsset;           // Token to sell
    address takerAsset;           // Token to buy
    uint256 makingAmount;         // Total amount to sell
    uint256 takingAmount;         // Total amount to receive
    uint256 salt;                 // Unique identifier
    uint256 expiration;           // Order expiration
    bool allowPartialFill;        // Allow partial fills

    // TWAP-specific fields
    uint256 twapStartTime;        // When TWAP can begin
    uint256 twapEndTime;          // When TWAP must end
    uint256 twapParts;            // Number of executions (1-100)
    uint256 maxPriceDeviation;    // Max price deviation in bps (e.g., 500 = 5%)
    uint256 executorTipBps;       // Executor tip in bps (e.g., 10 = 0.1%)
}
```

### Example TWAP Order

```javascript
// Sell 1000 USDC for ETH over 4 hours in 10 parts
const twapOrder = {
  makerAsset: "0xA0b86a33E6441E6C7D3E4C5B", // USDC
  takerAsset: "0xC02aaA39b223FE8D0A0e5C4F", // WETH
  makingAmount: "1000000000", // 1000 USDC
  takingAmount: "500000000000000000", // 0.5 ETH
  salt: "12345",
  expiration: Math.floor(Date.now() / 1000) + 86400, // 24 hours
  allowPartialFill: true,
  twapStartTime: Math.floor(Date.now() / 1000), // Now
  twapEndTime: Math.floor(Date.now() / 1000) + 14400, // 4 hours
  twapParts: 10, // 10 executions
  maxPriceDeviation: 500, // 5% max deviation
  executorTipBps: 10, // 0.1% tip
};
```

### Execution Timeline

- **Part 0**: Executable immediately at `twapStartTime`
- **Part 1**: Executable after 24 minutes (4 hours / 10 parts)
- **Part 2**: Executable after 48 minutes
- **...**
- **Part 9**: Executable after 3.6 hours (handles any remainder)

### Price Protection

- Initial price is recorded when order is registered
- Each execution checks current price against initial price
- If deviation exceeds `maxPriceDeviation`, execution reverts
- Protects users from executing during unfavorable market conditions

## 1inch Limit Order Protocol Integration

This contract integrates with the [1inch Limit Order Protocol v4](https://portal.1inch.dev/documentation/contracts/limit-order-protocol/limit-order-introduction) to provide:

### Supported Networks

- **Ethereum**: `0x111111125421ca6dc452d289314280a0f8842a65`
- **BSC**: `0x111111125421ca6dc452d289314280a0f8842a65`
- **Polygon**: `0x111111125421ca6dc452d289314280a0f8842a65`
- **Arbitrum**: `0x111111125421ca6dc452d289314280a0f8842a65`
- **Optimism**: `0x111111125421ca6dc452d289314280a0f8842a65`

### EIP-1271 Signature Validation

The contract implements EIP-1271 to validate signatures for limit orders, allowing the 1inch protocol to verify that orders were authorized by the wallet owner.

### Order Management

- Orders are tracked with registration and cancellation status
- Automatic token approvals for the 1inch protocol
- Event emission for order lifecycle tracking

## Dependencies

- **OpenZeppelin Contracts**: For secure cryptographic utilities and ERC-20 interfaces
- **Foundry Standard Library**: For testing and development utilities
- **1inch Limit Order Protocol**: For decentralized limit order functionality

## Security Features

✅ **Signature-based Authorization**: All operations require valid signatures
✅ **Expiration Timestamps**: Orders and swaps have built-in expiration
✅ **Nonce-based Replay Protection**: Prevents transaction replay attacks
✅ **Balance Verification**: Ensures expected token transfers
✅ **Gas Cost Validation**: Verifies fee payments cover actual costs
✅ **EIP-1271 Compliance**: Standard smart contract signature validation
✅ **Price Protection**: TWAP orders protected from excessive price deviation
✅ **Time-based Execution**: TWAP parts can only execute at appropriate intervals
✅ **Executor Incentives**: Built-in tip system encourages reliable execution

## Use Cases

### For Traders

- **Large Order Execution**: Break large orders into smaller parts to reduce slippage
- **Dollar Cost Averaging**: Execute regular purchases over time
- **Reduced Market Impact**: Avoid moving markets with large single transactions
- **Price Protection**: Automatic halt if market conditions become unfavorable

### For Executors

- **Earn Tips**: Get paid for executing TWAP parts
- **MEV Opportunities**: Front-run TWAP executions within price protection limits
- **Automated Strategies**: Build bots to execute TWAP orders efficiently

### For Protocols

- **Integration Ready**: Easy integration with existing DeFi protocols
- **Gas Efficient**: Optimized for minimal gas usage
- **Composable**: Can be combined with other DeFi primitives

## License

MIT
