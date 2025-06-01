const axios = require("axios");

async function fetch1inchSwapData() {
  const API_KEY = "cllGwasDRYNamLCG1VQygiEZZsg94lv0";
  const CHAIN_ID = 10; // Optimism
  const USDC = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85";
  const ONEINCH = "0xAd42D013ac31486B73b6b059e748172994736426";
  const USER = "0xa11ceB73aB7888736F264A3502933178f0a18553";
  const AMOUNT = "200000"; // 0.2 USDC (6 decimals) - for regular swap
  const SLIPPAGE = 5;

  const url = `https://api.1inch.dev/swap/v6.0/${CHAIN_ID}/swap`;
  const params = {
    src: USDC,
    dst: ONEINCH,
    amount: AMOUNT,
    from: USER,
    slippage: SLIPPAGE,
    disableEstimate: true,
    allowPartialFill: false,
  };

  try {
    const response = await axios.get(url, {
      params,
      headers: {
        Authorization: `Bearer ${API_KEY}`,
        Accept: "application/json",
      },
    });

    const hexData = response.data.tx.data.substring(2); // Remove '0x' prefix

    // Ensure even number of hex characters
    const cleanHexData = hexData.length % 2 === 0 ? hexData : hexData + "0";

    // For FFI mode, output format: hexData|dstAmount
    if (process.argv.includes("--ffi")) {
      console.log(`${cleanHexData}|${response.data.dstAmount}`);
    } else {
      // Regular output for manual use
      console.log("// Fresh 1inch swap data");
      console.log(`// Expected output: ${response.data.dstAmount} wei 1INCH`);
      console.log(`// Gas estimate: ${response.data.tx.gas}`);
      console.log(`// Hex length: ${cleanHexData.length} (should be even)`);
      console.log("");
      console.log(`bytes memory swapData = hex"${cleanHexData}";`);
      console.log("");
      console.log("// Raw response for debugging:");
      console.log(JSON.stringify(response.data, null, 2));
    }
  } catch (error) {
    if (process.argv.includes("--ffi")) {
      console.log("ERROR");
    } else {
      console.error(
        "Error fetching 1inch data:",
        error.response?.data || error.message
      );
    }
  }
}

fetch1inchSwapData();
