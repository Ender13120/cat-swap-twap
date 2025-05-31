import { Address, SignTypedDataReturnType } from "viem";

export const EIP_712_DOMAIN = {
  name: "Cat TWAP Swap",
  version: "1",
  chainId: 1, // You can modify this based on your target chain
} as const;

// The named list of all type definitions for TWAP orders
export const EIP_712_TYPE = {
  Token: [
    { name: "address", type: "address" },
    { name: "amount", type: "uint256" },
  ],
  TWAPOrder: [
    { name: "tokenIn", type: "Token" },
    { name: "tokenOut", type: "Token" },
    { name: "rate", type: "uint256" },
    { name: "slippage", type: "uint256" },
    { name: "parts", type: "uint256" },
    { name: "duration", type: "uint256" },
    { name: "owner", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

export function generateTWAPOrder({
  tokenInAddress,
  tokenInAmount,
  tokenOutAddress,
  tokenOutAmount,
  rate,
  slippage,
  parts,
  duration,
  ownerAddress,
  nonce = Date.now(),
}: {
  tokenInAddress: string;
  tokenInAmount: string;
  tokenOutAddress: string;
  tokenOutAmount: string;
  rate: string;
  slippage: string;
  parts: string;
  duration: string;
  ownerAddress?: string;
  nonce?: number;
}) {
  const deadline = Math.floor(Date.now() / 1000) + parseInt(duration || "3600");
  
  return {
    tokenIn: {
      address: tokenInAddress || "0x0000000000000000000000000000000000000000",
      amount: BigInt(tokenInAmount || "0"),
    },
    tokenOut: {
      address: tokenOutAddress || "0x0000000000000000000000000000000000000000",
      amount: BigInt(tokenOutAmount || "0"),
    },
    rate: BigInt(rate || "0"),
    slippage: BigInt(slippage || "0"),
    parts: BigInt(parts || "1"),
    duration: BigInt(duration || "3600"), // 1 hour default
    owner: ownerAddress || "0x0000000000000000000000000000000000000000",
    nonce: BigInt(nonce),
    deadline: BigInt(deadline),
  };
}

export type VerifyRequestBody = {
  tokenInAddress: string;
  tokenInAmount: string;
  tokenOutAddress: string;
  tokenOutAmount: string;
  rate: string;
  slippage: string;
  parts: string;
  duration: string;
  signature: SignTypedDataReturnType;
  signer: Address;
};
