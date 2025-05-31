# DelegatedWallet with 1inch TWAP Integration

A comprehensive smart contract system implementing EIP-7702 delegated execution with advanced trading features including Dutch auctions, 1inch limit orders, and Time-Weighted Average Price (TWAP) orders.

## 🚀 Features

### Core Functionality

- **EIP-7702 Delegated Execution**: Batch operations with gas fee payment
- **Dutch Auction Swaps**: Dynamic pricing with time-based decay
- **1inch Limit Orders**: Integration with 1inch Limit Order Protocol
- **TWAP Orders**: Distributed execution with executor incentives
- **Batch Swap Orders**: Sign once, execute multiple swaps over time
- **EIP-1271 Signature Validation**: Smart contract signature support

### Advanced Trading Features

- **Sign Once, Execute Many**: Users sign comprehensive TWAP orders once
- **Executor Incentives**: Automatic tip distribution via 1inch integrator fees
- **Price Protection**: Maximum deviation limits for TWAP executions
- **Time-based Scheduling**: Automated execution timing for TWAP parts
- **Batch Swap Automation**: Execute multiple swaps with configurable delays
- **Gas Optimization**: Efficient batch operations and IR optimization

## 📁 Project Structure

```
cat-swap-twap/
├── src/
│   └── Firstdraft.sol          # Main DelegatedWallet contract
├── script/
│   ├── RegisterBatchSwap.s.sol # Register batch swap orders
│   ├── ExecuteBatchPart.s.sol  # Execute individual batch parts
│   └── Send7702.s.sol          # Foundry demo script
├── scripts/
│   └── submit-1inch-orders.ts  # 1inch API integration script
├── execute-batch-swap-complete.sh # Complete batch swap automation
├── lib/                        # Foundry dependencies
├── foundry.toml               # Foundry configuration
├── package.json               # Node.js dependencies
├── tsconfig.json              # TypeScript configuration
└── env.example                # Environment variables template
```

## 🛠 Installation & Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (v18+)
- [1inch API Key](https://portal.1inch.dev/)

### Installation

1. **Clone and setup Foundry dependencies:**

```bash
git clone <repository>
cd cat-swap-twap
forge install
```

2. **Install Node.js dependencies:**

```bash
npm install
```

3. **Setup environment variables:**

```bash
cp env.example .env
# Edit .env with your actual values
```

4. **Compile contracts:**

```bash
forge build
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file with the following variables:

```bash
# RPC Configuration
RPC_URL=https://eth.llamarpc.com

# 1inch API Configuration
ONEINCH_API_KEY=your_1inch_api_key_here

# Private Keys (for testing only)
USER_PK2=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
EXECUTOR_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
SPONSOR_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
```

⚠️ **Security Warning**: The example private keys are well-known test keys. NEVER use them with real funds!

### Contract Addresses

The system integrates with these deployed contracts:

- **1inch Limit Order Protocol**: `0x111111125421cA6dc452d289314280a0f8842A65` (Ethereum)
- **USDC**: `0xA0b86a33E6441E6C7D3E4C5B27eAb5B2B5e6E4A0` (Example)
- **WETH**: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` (Ethereum)

## 🎯 Usage

### 1. Foundry Demo Script

Run the comprehensive Solidity demo:

```bash
forge script script/Send7702.s.sol --rpc-url $RPC_URL --private-key $SPONSOR_PK --broadcast
```

This demonstrates:

- Batch execution with EIP-7702 delegation
- Dutch auction swap creation
- 1inch limit order registration
- TWAP order setup and configuration

### 2. 1inch API Integration

Run the TypeScript integration script:

```bash
# Development mode with ts-node
npm run dev

# Or compile and run
npm run build
npm start
```

This script demonstrates:

- **Limit Order Submission**: Creating and submitting orders to 1inch API
- **TWAP Order Management**: Registering TWAP orders with the contract
- **TWAP Part Execution**: Automated execution of TWAP parts with integrator fees
- **Order Status Tracking**: Monitoring order states and execution progress

### 3. Batch Swap Automation

Execute multiple swaps with a single signature using the batch swap system:

#### Quick Start - Complete Automation

```bash
# Run everything (register + execute all parts)
./execute-batch-swap-complete.sh

# Custom parameters: [NUM_PARTS] [DELAY_SECONDS]
./execute-batch-swap-complete.sh 2 15  # 2 parts with 15-second delays
```

#### Manual Step-by-Step

```bash
# Step 1: Register a batch order (as USER)
forge script script/RegisterBatchSwap.s.sol --rpc-url $RPC_URL --broadcast --slow

# Step 2: Execute parts individually (as SPONSOR)
BATCH_ORDER_HASH=0x... forge script script/ExecuteBatchPart.s.sol --rpc-url $RPC_URL --broadcast --ffi --slow
# Wait 5+ seconds between executions
```

#### What It Does

The batch swap system allows:

- **One Signature**: User signs once for all swaps
- **Multiple Executions**: Split large swaps into smaller parts
- **Time Delays**: Configurable minimum time between executions
- **Gas Sponsorship**: Sponsor pays gas for all executions
- **Price Protection**: Max deviation limits and Dutch auction pricing

Total execution time: ~3 minutes for 4 parts with 10-second delays

### 4. Manual Contract Interaction

You can also interact with the contract directly:

```solidity
// Deploy or connect to DelegatedWallet
DelegatedWallet wallet = DelegatedWallet(payable(userAddress));

// Register a TWAP order
LimitOrder memory twapOrder = LimitOrder({
    makerAsset: USDC,
    takerAsset: WETH,
    makingAmount: 5000 * 1e6,  // 5000 USDC
    takingAmount: 1.5 * 1e18,  // 1.5 ETH
    twapParts: 10,             // 10 executions
    twapStartTime: block.timestamp + 1 hours,
    twapEndTime: block.timestamp + 5 hours,
    maxPriceDeviation: 500,    // 5% max deviation
    executorTipBps: 10,        // 0.1% tip
    // ... other parameters
});

bytes32 orderHash = wallet.registerTWAPOrder(twapOrder, signature, initialPrice);
```

## 📊 Trading Examples

### Dutch Auction Swap

```typescript
const swapOrder = {
    tokenOut: USDC,
    tokenIn: WETH,
    amountOut: 500 * 1e6,      // 500 USDC
    minAmountIn: 0.15 * 1e18,  // 0.15 ETH minimum
    startPremiumBps: 200,      // 2% starting premium
    decayRateBps: 10,          // 0.1% decay per interval
    decayInterval: 60,         // 60 seconds per decay
    expiration: block.timestamp + 1 hours
};
```

### TWAP Order

```typescript
const twapOrder = {
  makingAmount: 5000 * 1e6, // 5000 USDC total
  takingAmount: 1.5 * 1e18, // 1.5 ETH total
  twapParts: 10, // 10 separate executions
  duration: 4 * 3600, // 4 hours total
  maxPriceDeviation: 500, // 5% max price movement
  executorTipBps: 10, // 0.1% tip per execution
};
```

### Batch Swap Order

```typescript
const batchOrder = {
    tokenOut: USDC,
    tokenIn: ONEINCH,
    totalAmountOut: 200000,        // 0.2 USDC total
    minAmountInPerPart: 0.01e18,   // Min 0.01 1INCH per part
    batchParts: 4,                 // 4 executions
    minTimeBetweenExecutions: 5,   // 5 seconds minimum
    maxPriceDeviation: 500,        // 5% max deviation
    executorTipBps: 10,            // 0.1% tip
    expiration: block.timestamp + 1 hours
};
```

## 🔐 Security Features

### Signature Validation

- **EIP-1271 Support**: Smart contract signature validation
- **Replay Protection**: Nonce-based protection against replay attacks
- **Expiration Handling**: Time-based order expiration
- **Price Protection**: Maximum deviation limits for TWAP orders

### Access Control

- **Owner-only Functions**: Critical functions restricted to contract owner
- **Signature Verification**: All operations require valid signatures
- **Time-based Validation**: Orders respect start/end time constraints

## 🏗 Architecture

### Contract Components

1. **DelegatedWallet**: Main contract implementing all functionality
2. **Batch Execution**: EIP-7702 delegated operations with gas payment
3. **Dutch Auction**: Time-based dynamic pricing system
4. **1inch Integration**: Limit order protocol integration
5. **TWAP System**: Distributed execution with executor incentives

### Integration Flow

```
User Signs TWAP Order
        ↓
Contract Registers Order
        ↓
Executors Monitor Timing
        ↓
Execute TWAP Parts via 1inch
        ↓
1inch Fills Orders + Pays Integrator Fees
        ↓
Contract Receives Tokens + Executors Get Tips
```

## 🧪 Testing

Run the test suite:

```bash
# Compile contracts
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test
forge test --match-test testTWAPExecution
```

## 📈 Gas Optimization

The contract includes several gas optimizations:

- **IR Optimizer**: Enabled in `foundry.toml` for complex functions
- **Batch Operations**: Multiple calls in single transaction
- **Efficient Storage**: Optimized struct packing
- **1inch Integrator Fees**: Gas-efficient tip distribution

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimers

- **Testnet Only**: This code is for educational and testing purposes
- **Security Audits**: Not audited - do not use with real funds
- **API Dependencies**: Requires 1inch API access for full functionality
- **EIP-7702**: Experimental standard - implementation may change

## 🔗 Resources

- [1inch Limit Order SDK](https://github.com/1inch/limit-order-sdk)
- [EIP-7702 Specification](https://eips.ethereum.org/EIPS/eip-7702)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [1inch Developer Portal](https://portal.1inch.dev/)

## 📞 Support

For questions and support:

- Open an issue on GitHub
- Check the documentation
- Review the example scripts
- Test on testnets first
