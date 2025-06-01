import { NextRequest, NextResponse } from 'next/server'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { swapOrder, signature, signer } = body

    // Log the received data for debugging
    console.log('Received TWAP submission:')
    console.log('Swap Order:', swapOrder)
    console.log('Signature:', signature)
    console.log('Signer:', signer)

    // Validate required fields
    if (!swapOrder || !signature || !signer) {
      return NextResponse.json(
        { error: 'Missing required fields: swapOrder, signature, or signer' },
        { status: 400 }
      )
    }

    // Validate swap order fields and auto-set timestamp
    const currentTimestamp = Math.floor(Date.now() / 1000) // Current Unix timestamp
    
    // Auto-update timestamp to current time
    if (swapOrder.timestamp !== currentTimestamp.toString()) {
      console.log(`Updating timestamp from ${swapOrder.timestamp} to current timestamp: ${currentTimestamp}`)
      swapOrder.timestamp = currentTimestamp.toString()
    }
    
    const requiredFields = ['tokenIn', 'tokenOut', 'amountOut', 'minAmountIn', 'timestamp', 'expiration', 'nonce']
    for (const field of requiredFields) {
      if (!swapOrder[field]) {
        return NextResponse.json(
          { error: `Missing required swap order field: ${field}` },
          { status: 400 }
        )
      }
    }

    // Validate that nonce appears to be fetched from blockchain (should be a positive number)
    const nonce = parseInt(swapOrder.nonce)
    if (isNaN(nonce) || nonce < 0) {
      return NextResponse.json(
        { error: 'Invalid nonce - must fetch latest nonce from blockchain' },
        { status: 400 }
      )
    }

    // Stub processing - in a real implementation, you would:
    // 1. Verify the signature
    // 2. Validate the swap order parameters
    // 3. Submit to your TWAP execution system
    // 4. Return transaction hash or order ID

    // Simulate processing delay
    await new Promise(resolve => setTimeout(resolve, 1000))

    // Return success response with mock transaction hash
    const mockTxHash = `0x${Math.random().toString(16).substr(2, 64)}`
    
    return NextResponse.json({
      success: true,
      message: 'TWAP order submitted successfully',
      transactionHash: mockTxHash,
      orderId: `order_${Date.now()}`,
      swapOrder,
      timestamp: new Date().toISOString()
    })

  } catch (error) {
    console.error('Error processing TWAP submission:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
} 