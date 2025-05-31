"use client";

import { useEffect, useState } from "react";
import type { NextPage } from "next";
import { SignTypedDataReturnType } from "viem/accounts";
import { useAccount, useSignTypedData, useVerifyTypedData } from "wagmi";
import { EIP_712_DOMAIN, EIP_712_TYPE, VerifyRequestBody, generateTWAPOrder } from "~~/utils/eip-712";
import { getParsedError, notification } from "~~/utils/scaffold-eth";

const Eip712: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const [signature, setSignature] = useState<SignTypedDataReturnType>();
  const [signedTypedData, setSignedTypedData] = useState<Record<string, unknown>>();
  const [isLoading, setIsLoading] = useState(false);
  const { signTypedDataAsync } = useSignTypedData();

  // TWAP Order state variables
  const [tokenInAddress, setTokenInAddress] = useState("");
  const [tokenInAmount, setTokenInAmount] = useState("");
  const [tokenOutAddress, setTokenOutAddress] = useState("");
  const [tokenOutAmount, setTokenOutAmount] = useState("");
  const [rate, setRate] = useState("");
  const [slippage, setSlippage] = useState("");
  const [parts, setParts] = useState("");
  const [duration, setDuration] = useState("");

  const typedData = {
    domain: EIP_712_DOMAIN,
    types: EIP_712_TYPE,
    primaryType: "TWAPOrder",
    message: generateTWAPOrder({
      tokenInAddress,
      tokenInAmount,
      tokenOutAddress,
      tokenOutAmount,
      rate,
      slippage,
      parts,
      duration,
      ownerAddress: connectedAddress,
    }),
  } as const;

  const { data: verifiedOnFrontend } = useVerifyTypedData({
    ...typedData,
    address: connectedAddress,
    signature,
  });

  const signTypedData = async () => {
    try {
      const signature = await signTypedDataAsync(typedData);
      setSignature(signature);
      setSignedTypedData(typedData);
      return signature;
    } catch (e) {
      const errorMessage = getParsedError(e);
      notification.error(errorMessage);
    }
  };

  const verifyOnFrontend = () => {
    if (verifiedOnFrontend) {
      notification.success("TWAP Order verified successfully!");
      return;
    }

    notification.error("TWAP Order verification failed");
  };

  const verifyOnBackend = async () => {
    if (!connectedAddress) {
      notification.info("Connect your wallet");
      return;
    }

    if (!signature) {
      notification.info("TWAP order is not signed");
      return;
    }

    const requestBody: VerifyRequestBody = {
      tokenInAddress,
      tokenInAmount,
      tokenOutAddress,
      tokenOutAmount,
      rate,
      slippage,
      parts,
      duration,
      signature,
      signer: connectedAddress,
    };

    setIsLoading(true);

    try {
      const res = await fetch("/api/verify", {
        method: "POST",
        body: JSON.stringify(requestBody),
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.error || `Error verifying TWAP order on backend`);
      }
      notification.success("TWAP Order verified successfully!");
    } catch (err) {
      const errorMessage = getParsedError(err);
      notification.error(errorMessage);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (!connectedAddress) {
      setSignature(undefined);
      setSignedTypedData(undefined);
    }
  }, [connectedAddress]);

  return (
    <div className="flex items-center flex-col flex-grow pt-10 px-8">
      <div className="flex flex-col gap-4 items-center text-center">
        <h1 className="text-2xl font-bold">Cat TWAP Swap - EIP-712</h1>
        <div className="max-w-2xl">
          Create and sign Time-Weighted Average Price (TWAP) orders using EIP-712 structured data signing. 
          TWAP orders allow you to split large trades into smaller parts executed over time to reduce market impact and achieve better average prices.
        </div>

        <div className="divider my-0" />
        <div className="divider my-0" />

        <div className="text-xl font-bold">Create TWAP Order</div>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 w-full max-w-4xl">
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Token In Address</label>
            <input
              placeholder="0x..."
              className="input input-bordered rounded-lg w-full"
              value={tokenInAddress}
              onChange={e => setTokenInAddress(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Token In Amount</label>
            <input
              placeholder="1000000000000000000"
              className="input input-bordered rounded-lg w-full"
              value={tokenInAmount}
              onChange={e => setTokenInAmount(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Token Out Address</label>
            <input
              placeholder="0x..."
              className="input input-bordered rounded-lg w-full"
              value={tokenOutAddress}
              onChange={e => setTokenOutAddress(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Token Out Amount</label>
            <input
              placeholder="2000000000000000000"
              className="input input-bordered rounded-lg w-full"
              value={tokenOutAmount}
              onChange={e => setTokenOutAmount(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Exchange Rate</label>
            <input
              placeholder="1500000000000000000"
              className="input input-bordered rounded-lg w-full"
              value={rate}
              onChange={e => setRate(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Slippage (basis points)</label>
            <input
              placeholder="100"
              className="input input-bordered rounded-lg w-full"
              value={slippage}
              onChange={e => setSlippage(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Number of sub-orders</label>
            <input
              placeholder="10"
              className="input input-bordered rounded-lg w-full"
              value={parts}
              onChange={e => setParts(e.target.value)}
            />
          </div>
          
          <div className="flex flex-col gap-2">
            <label className="font-semibold text-left">Duration (seconds)</label>
            <input
              placeholder="3600"
              className="input input-bordered rounded-lg w-full"
              value={duration}
              onChange={e => setDuration(e.target.value)}
            />
          </div>
        </div>

        <span className="text-sm text-gray-600">
          Use Metamask or another wallet supporting &quot;eth_signTypedData_v4&quot; to review and sign your TWAP order.
        </span>

        <button className="btn btn-primary btn-sm" onClick={signTypedData} disabled={!connectedAddress}>
          Sign TWAP Order
        </button>

        <details className="collapse collapse-arrow bg-base-300 !max-w-full">
          <input type="checkbox" className="hidden" />
          <summary className="collapse-title font-bold">Current TWAP Order Data</summary>
          <div className="collapse-content text-start">
            <pre className="break-all">{JSON.stringify(typedData, (key, value) =>typeof value === 'bigint'?value.toString():value, 2)}</pre>
          </div>
        </details>

        {signature && signedTypedData && (
          <details className="collapse collapse-arrow bg-base-300">
            <input type="checkbox" className="hidden" />
            <summary className="collapse-title font-bold">Signed TWAP Order</summary>
            <div className="collapse-content text-start">
              <pre>{JSON.stringify(signedTypedData, undefined, 2)}</pre>
            </div>
          </details>
        )}

        {signature && (
          <div className="text-center max-w-2xl bg-base-300 p-4 rounded-2xl">
            <div className="font-bold">Order Signature:</div>
            <div className="break-all">{signature}</div>
          </div>
        )}

        <div className="max-w-2xl">
          To successfully verify, the current TWAP order data and signed order data must be equal. The signature proves 
          ownership and intent to execute this specific TWAP order with the given parameters.
        </div>
        <button className="btn btn-primary btn-sm" onClick={verifyOnFrontend} disabled={!signature}>
          Verify Order (frontend)
        </button>
        <button className={`btn btn-primary btn-sm`} onClick={verifyOnBackend} disabled={!signature || isLoading}>
          {isLoading && <span className="loading loading-spinner" />}
          Verify Order (backend)
        </button>
      </div>
    </div>
  );
};

export default Eip712;
