'use client'

import { useAccount, useConnect, useDisconnect, useReadContract, useSignMessage, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { useState, useEffect } from 'react'
import { encodePacked, encodeAbiParameters, keccak256, parseAbiParameters } from 'viem'
import { USDC_CONFIG, ONEINCH_CONFIG, DELEGATED_WALLET_CONFIG } from '../../contracts'

function App() {
  const account = useAccount()
  const { connectors, connect, status, error } = useConnect()
  const { disconnect } = useDisconnect()
  const { signMessageAsync, isPending: isSigningPending, error: signError } = useSignMessage()
  const { writeContract, isPending: isWritePending, error: writeError, data: txHash } = useWriteContract()
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash: txHash,
  })

  // Fetch USDC balance when account is connected
  const { data: usdcBalance, isLoading: isLoadingBalance } = useReadContract({
    address: USDC_CONFIG.address as `0x${string}`,
    abi: USDC_CONFIG.abi,
    functionName: 'balanceOf',
    args: account.address ? [account.address] : undefined,
    query: {
      enabled: !!account.address, // Only fetch when account is connected
    },
  })

  // Swap order state - corrected token addresses to match .sol file
  const [swapOrder, setSwapOrder] = useState({
    tokenOut: '0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85', // USDC (selling)
    tokenIn: '0xAd42D013ac31486B73b6b059e748172994736426', // 1INCH (buying)
    amountOut: '',
    minAmountIn: '',
    timestamp: '',
    expiration: '',
    numberOfParts: '4', // Default from .sol file (BATCH_PARTS = 4)
    delayBetweenParts: '5', // Default from .sol file (TIME_BETWEEN_PARTS = 5)
    // Add missing values with defaults from .sol file
    maxPriceDeviation: '500', // 5%
    executorTipBps: '10', // 0.1%
    startPremiumBps: '0', // No Dutch auction
    decayRateBps: '0',
    decayInterval: '60'
  })

  const [isSubmitting, setIsSubmitting] = useState(false)
  const [submitResult, setSubmitResult] = useState<string | null>(null)

  // Constants from .sol file
  const WALLET_ADDRESS = '0xa11cCD98850c568eA86d964dabE7afeB085b7DFe'
  const OPTIMISM_CHAIN_ID = BigInt(10) // Optimism mainnet

  // Format balance for display (USDC has 6 decimals)
  const formatUsdcBalance = (balance: any) => {
    if (!balance) return '0'
    return (Number(balance) / 1000000).toFixed(6) // Convert from wei to USDC (6 decimals)
  }

  // Update minAmountIn when USDC balance is loaded
  useEffect(() => {
    if (usdcBalance && !isLoadingBalance) {
      const formattedBalance = formatUsdcBalance(usdcBalance)
      setSwapOrder(prev => ({
        ...prev,
        minAmountIn: formattedBalance
      }))
    }
  }, [usdcBalance, isLoadingBalance])

  // Auto-fetch timestamp when account changes
  useEffect(() => {
    if (account.address) {
      // Auto-set current timestamp
      const currentTimestamp = Math.floor(Date.now() / 1000).toString()
      console.log('Auto-setting current timestamp:', currentTimestamp)
      
      setSwapOrder(prev => ({
        ...prev,
        timestamp: currentTimestamp,
        expiration: (parseInt(currentTimestamp) + 3600).toString() // 1 hour from now
      }))
    }
  }, [account.address])

  // Handle transaction confirmation
  useEffect(() => {
    if (isConfirmed && txHash) {
      setSubmitResult(`TWAP order registered successfully! Transaction: ${txHash}`)
      setIsSubmitting(false)
    }
  }, [isConfirmed, txHash])

  // Handle write errors
  useEffect(() => {
    if (writeError) {
      setSubmitResult(`Transaction failed: ${writeError.message}`)
      setIsSubmitting(false)
    }
  }, [writeError])

  // Helper function to update timestamp to current time
  const updateToCurrentTimestamp = () => {
    const currentTimestamp = Math.floor(Date.now() / 1000).toString()
    setSwapOrder(prev => ({
      ...prev,
      timestamp: currentTimestamp,
      expiration: (parseInt(currentTimestamp) + 3600).toString() // 1 hour from now
    }))
  }

  const handleInputChange = (field: string, value: string) => {
    setSwapOrder(prev => ({
      ...prev,
      [field]: value
    }))
  }

  const handleSubmitSwapOrder = (e: React.FormEvent) => {
    e.preventDefault()
    console.log('Swap Order:', swapOrder)
    // Handle swap order submission here
  }

  const handleSubmitTWAP = async () => {
    if (!account.address) {
      alert('Please connect your wallet first')
      return
    }

    try {
      setIsSubmitting(true)
      setSubmitResult(null)

      // Create order hash using same encoding as RegisterBatchSwap.s.sol
      const orderHash = keccak256(
        encodeAbiParameters(
          parseAbiParameters([
            'address', // tokenOut
            'address', // tokenIn  
            'uint256', // totalAmountOut
            'uint256', // minAmountInPerPart
            'uint256', // timestamp
            'uint256', // expiration
            'uint256', // batchParts
            'uint256', // minTimeBetweenExecutions
            'uint256', // maxPriceDeviation
            'uint256', // executorTipBps
            'uint256', // startPremiumBps
            'uint256', // decayRateBps
            'uint256', // decayInterval
            'uint256', // chainId
            'address'  // wallet address
          ]),
          [
            swapOrder.tokenOut as `0x${string}`,
            swapOrder.tokenIn as `0x${string}`,
            BigInt(Math.floor(parseFloat(swapOrder.amountOut || '0') * 1000000)), // Convert to USDC wei (6 decimals)
            BigInt(Math.floor(parseFloat(swapOrder.minAmountIn || '0') * 1e18)), // Convert to 1INCH wei (18 decimals)
            BigInt(swapOrder.timestamp || '0'),
            BigInt(swapOrder.expiration || '0'),
            BigInt(swapOrder.numberOfParts || '4'),
            BigInt(swapOrder.delayBetweenParts || '5'),
            BigInt(swapOrder.maxPriceDeviation || '500'),
            BigInt(swapOrder.executorTipBps || '10'),
            BigInt(swapOrder.startPremiumBps || '0'),
            BigInt(swapOrder.decayRateBps || '0'),
            BigInt(swapOrder.decayInterval || '60'),
            OPTIMISM_CHAIN_ID,
            WALLET_ADDRESS as `0x${string}`
          ]
        )
      )

      console.log('Order hash:', orderHash)

      // Create message hash using same format as .sol file
      const messageHash = keccak256(
        encodePacked(
          ['string', 'bytes32'],
          ['\x19Ethereum Signed Message:\n32', orderHash]
        )
      )

      console.log('Message hash to sign:', messageHash)

      // Sign the message hash (viem expects hex string)
      const signature = await signMessageAsync({ message: { raw: messageHash } })
      console.log('Signature generated:', signature)

      // Prepare batch order struct for contract call
      const batchOrder = {
        tokenOut: swapOrder.tokenOut as `0x${string}`,
        tokenIn: swapOrder.tokenIn as `0x${string}`,
        totalAmountOut: BigInt(swapOrder.amountOut || '0'),
        minAmountInPerPart: BigInt(swapOrder.minAmountIn || '0'),
        timestamp: BigInt(swapOrder.timestamp || '0'),
        expiration: BigInt(swapOrder.expiration || '0'),
        orderHash: '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`, // Will be generated by contract
        batchParts: BigInt(swapOrder.numberOfParts || '4'),
        minTimeBetweenExecutions: BigInt(swapOrder.delayBetweenParts || '5'),
        maxPriceDeviation: BigInt(swapOrder.maxPriceDeviation || '500'),
        executorTipBps: BigInt(swapOrder.executorTipBps || '10'),
        startPremiumBps: BigInt(swapOrder.startPremiumBps || '0'),
        decayRateBps: BigInt(swapOrder.decayRateBps || '0'),
        decayInterval: BigInt(swapOrder.decayInterval || '60')
      }

      // Call the contract function
      writeContract({
        address: DELEGATED_WALLET_CONFIG.address as `0x${string}`,
        abi: DELEGATED_WALLET_CONFIG.abi,
        functionName: 'registerBatchSwapOrder',
        args: [batchOrder, signature as `0x${string}`]
      })

    } catch (err) {
      console.error('Error submitting TWAP:', err)
      setSubmitResult(`Error: ${err instanceof Error ? err.message : 'Unknown error'}`)
      setIsSubmitting(false)
    }
  }

  return (
    <>
      <div>
        <h2>Account</h2>

        <div>
          status: {account.status}
          {account.address && (
            <>
              <br />
              USDC Balance: {isLoadingBalance ? 'Loading...' : `${formatUsdcBalance(usdcBalance)} USDC`}
            </>
          )}
          <br />
          addresses: {JSON.stringify(account.addresses)}
          <br />
          chainId: {account.chainId}
        </div>

        {account.status === 'connected' && (
          <button type="button" onClick={() => disconnect()}>
            Disconnect
          </button>
        )}
      </div>

      <div>
        <h2>Connect</h2>
        {connectors.map((connector) => (
          <button
            key={connector.uid}
            onClick={() => connect({ connector })}
            type="button"
          >
            {connector.name}
          </button>
        ))}
        <div>{status}</div>
        <div>{error?.message}</div>
      </div>

      <div>
        <h2>Batch Swap Order (TWAP)</h2>
        <form onSubmit={handleSubmitSwapOrder} style={{ display: 'flex', flexDirection: 'column', gap: '10px', maxWidth: '400px' }}>
          <div>
            <label>Token Out (Selling - USDC):</label>
            <input 
              type="text" 
              value={swapOrder.tokenOut} 
              disabled 
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <div>
            <label>Token In (Buying - 1INCH):</label>
            <input 
              type="text" 
              value={swapOrder.tokenIn} 
              disabled 
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <div>
            <label>Amount Out (USDC to sell):</label>
            <input 
              type="number" 
              step="0.000001"
              value={swapOrder.amountOut}
              onChange={(e) => handleInputChange('amountOut', e.target.value)}
              placeholder="Enter USDC amount to sell"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <div>
            <label>Min Amount In (1INCH per part):</label>
            <input 
              type="number" 
              step="0.000000000000000001"
              value={swapOrder.minAmountIn}
              onChange={(e) => handleInputChange('minAmountIn', e.target.value)}
              placeholder="Minimum 1INCH tokens per part"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <div>
            <label>Timestamp:</label>
            <input 
              type="number" 
              value={swapOrder.timestamp}
              onChange={(e) => handleInputChange('timestamp', e.target.value)}
              placeholder="Auto-set to current time"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
            <button 
              type="button" 
              onClick={updateToCurrentTimestamp}
              style={{ marginLeft: '5px', padding: '5px', fontSize: '12px' }}
            >
              🔄 Use Current Time
            </button>
          </div>
          
          <div>
            <label>Expiration:</label>
            <input 
              type="number" 
              value={swapOrder.expiration}
              onChange={(e) => handleInputChange('expiration', e.target.value)}
              placeholder="Auto-set to timestamp + 1 hour"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <div>
            <label>Number of Parts:</label>
            <input 
              type="number" 
              value={swapOrder.numberOfParts}
              onChange={(e) => handleInputChange('numberOfParts', e.target.value)}
              placeholder="Number of parts (default: 4)"
              min="1"
              max="100"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <div>
            <label>Delay Between Parts (seconds):</label>
            <input 
              type="number" 
              value={swapOrder.delayBetweenParts}
              onChange={(e) => handleInputChange('delayBetweenParts', e.target.value)}
              placeholder="Delay in seconds (default: 5)"
              min="1"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>

          <div>
            <label>Max Price Deviation (bps):</label>
            <input 
              type="number" 
              value={swapOrder.maxPriceDeviation}
              onChange={(e) => handleInputChange('maxPriceDeviation', e.target.value)}
              placeholder="Max price deviation in basis points (default: 500 = 5%)"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>

          <div>
            <label>Executor Tip (bps):</label>
            <input 
              type="number" 
              value={swapOrder.executorTipBps}
              onChange={(e) => handleInputChange('executorTipBps', e.target.value)}
              placeholder="Executor tip in basis points (default: 10 = 0.1%)"
              style={{ marginLeft: '10px', padding: '5px' }}
            />
          </div>
          
          <button 
            type="button" 
            onClick={handleSubmitTWAP}
            disabled={isSubmitting || isSigningPending || isWritePending || isConfirming || !account.address}
            style={{ 
              padding: '10px', 
              marginTop: '10px', 
              backgroundColor: '#007bff', 
              color: 'white', 
              border: 'none', 
              borderRadius: '4px',
              cursor: account.address ? 'pointer' : 'not-allowed',
              opacity: (isSubmitting || isSigningPending || isWritePending || isConfirming || !account.address) ? 0.6 : 1
            }}
          >
            {isSigningPending ? 'Signing...' : 
             isWritePending ? 'Sending Transaction...' : 
             isConfirming ? 'Confirming...' : 
             'Submit TWAP Order'}
          </button>
          
          {signError && (
            <div style={{ color: 'red', marginTop: '10px' }}>
              Sign Error: {signError.message}
            </div>
          )}

          {writeError && (
            <div style={{ color: 'red', marginTop: '10px' }}>
              Transaction Error: {writeError.message}
            </div>
          )}
          
          {submitResult && (
            <div style={{ 
              marginTop: '10px', 
              padding: '10px', 
              backgroundColor: submitResult.includes('Error') || submitResult.includes('failed') ? '#f8d7da' : '#d4edda',
              color: submitResult.includes('Error') || submitResult.includes('failed') ? '#721c24' : '#155724',
              borderRadius: '4px'
            }}>
              {submitResult}
            </div>
          )}
        </form>
      </div>
    </>
  )
}

export default App
