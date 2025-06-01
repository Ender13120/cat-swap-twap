const axios = require("axios");

async function fetch1inchSwap() {
  try {
    const USDC = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85";
    const ONEINCH = "0xAd42D013ac31486B73b6b059e748172994736426";
    const USER = "0xa11ceB73aB7888736F264A3502933178f0a18553";
    const AMOUNT = "50000"; // 0.05 USDC (6 decimals) - for batch parts
    const SLIPPAGE = 5;

    const url = `https://api.1inch.dev/swap/v6.0/10/swap?src=${USDC}&dst=${ONEINCH}&amount=${AMOUNT}&from=${USER}&slippage=${SLIPPAGE}&disableEstimate=true&allowPartialFill=false`;

    const response = await axios.get(url, {
      headers: {
        Authorization: `Bearer ${process.env.ONEINCH_API_KEY}`,
        Accept: "application/json",
      },
    });

    // Return format: hexData|dstAmount
    console.log(`${response.data.tx.data}|${response.data.dstAmount}`);
  } catch (error) {
    console.log("ERROR");
    process.exit(1);
  }
}

fetch1inchSwap();
