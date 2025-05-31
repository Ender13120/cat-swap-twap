# Cat Swap TWAP - Smart Contracts

A Solidity smart contract project for delegated wallet functionality with TWAP (Time-Weighted Average Price) features.

## Project Structure

```
cat-swap-twap/
├── src/                    # Smart contracts source code
│   └── Firstdraft.sol     # DelegatedWallet contract
├── test/                  # Test files
├── script/                # Deployment scripts
├── lib/                   # Dependencies
│   ├── forge-std/         # Foundry standard library
│   └── openzeppelin-contracts/  # OpenZeppelin contracts
├── out/                   # Compiled contracts (build artifacts)
├── foundry.toml          # Foundry configuration
└── README.md             # This file
```

## Features

The `DelegatedWallet` contract provides:

- **Batch Execution**: Execute multiple calls atomically
- **ERC-20 Fee Payment**: Pay transaction fees in any ERC-20 token
- **Gas Cost Verification**: Ensures fee covers actual gas costs
- **Signature Verification**: EOA signature authorization for operations
- **Nonce Protection**: Prevents replay attacks

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

- Executing arbitrary function calls in batches
- Paying sponsors in ERC-20 tokens for gas costs
- Verifying that token payments cover actual ETH gas costs
- Using cryptographic signatures for authorization

Key functions:

- `execute()`: Main function to execute a batch of calls with fee payment

## Dependencies

- **OpenZeppelin Contracts**: For secure cryptographic utilities and ERC-20 interfaces
- **Foundry Standard Library**: For testing and development utilities

## License

MIT
