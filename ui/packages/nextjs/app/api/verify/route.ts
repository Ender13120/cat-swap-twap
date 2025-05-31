import { NextResponse } from "next/server";
import { recoverTypedDataAddress } from "viem";
import { EIP_712_DOMAIN, EIP_712_TYPE, VerifyRequestBody, generateTWAPOrder } from "~~/utils/eip-712";

export async function POST(req: Request) {
  try {
    const { 
      tokenInAddress,
      tokenInAmount,
      tokenOutAddress,
      tokenOutAmount,
      rate,
      slippage,
      parts,
      duration,
      signature, 
      signer 
    } = (await req.json()) as VerifyRequestBody;

    const recoveredAddress = await recoverTypedDataAddress({
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
        ownerAddress: signer 
      }),
      signature,
    });

    if (recoveredAddress !== signer) {
      return NextResponse.json({ error: "Recovered address does not match signer" }, { status: 401 });
    }

    return NextResponse.json({ message: "TWAP Order verified successfully!" }, { status: 200 });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "Something went wrong verifying TWAP order" }, { status: 500 });
  }
}
