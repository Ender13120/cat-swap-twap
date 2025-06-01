#!/bin/bash

# Complete Batch Swap Script - Register and Execute All Parts
# Usage: ./execute-batch-swap-complete.sh [NUM_PARTS] [DELAY_SECONDS]

# Set default values
NUM_PARTS="${1:-4}"
DELAY_SECONDS="${2:-10}"
RPC_URL="https://opt-mainnet.g.alchemy.com/v2/uvOR0hUmSZ8aYOuuMDqytlg_vKN7IPTu"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== COMPLETE BATCH SWAP EXECUTION ===${NC}"
echo "Parts to execute: $NUM_PARTS"
echo "Delay between parts: $DELAY_SECONDS seconds"
echo ""

# Step 1: Register the batch order
echo -e "${YELLOW}STEP 1: Registering batch swap order...${NC}"

# Run registration and capture the output
REGISTER_OUTPUT=$(forge script script/RegisterBatchSwap.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --slow 2>&1)

# Check if registration was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Registration failed!${NC}"
    echo "$REGISTER_OUTPUT"
    exit 1
fi

# Extract the order hash from the output - look for the hex string after "Order Hash:"
ORDER_HASH=$(echo "$REGISTER_OUTPUT" | grep -A1 "Order Hash:" | tail -1 | grep -oE "0x[a-fA-F0-9]{64}" | head -1)

# If that didn't work, try another pattern
if [ -z "$ORDER_HASH" ]; then
    ORDER_HASH=$(echo "$REGISTER_OUTPUT" | grep -oE "0x[a-fA-F0-9]{64}" | tail -1)
fi

if [ -z "$ORDER_HASH" ]; then
    echo -e "${RED}✗ Could not extract order hash from registration output${NC}"
    echo "Registration output:"
    echo "$REGISTER_OUTPUT"
    echo ""
    echo -e "${YELLOW}But registration likely succeeded! Check the output above for the order hash.${NC}"
    echo "You can manually run the execution with:"
    echo "BATCH_ORDER_HASH=<your_order_hash> forge script script/ExecuteBatchPart.s.sol --rpc-url $RPC_URL --broadcast --ffi --slow"
    exit 1
fi

echo -e "${GREEN}✓ Batch order registered successfully!${NC}"
echo "Order Hash: $ORDER_HASH"

# Wait a bit after registration
echo -e "\n${YELLOW}Waiting 5 seconds after registration...${NC}"
sleep 5

# Step 2: Execute all parts
echo -e "\n${BLUE}STEP 2: Executing batch swap parts...${NC}"

# Function to execute a single part
execute_part() {
    local part_num=$1
    echo -e "\n${YELLOW}>>> Executing Part $part_num of $NUM_PARTS${NC}"
    
    # Execute the part
    BATCH_ORDER_HASH=$ORDER_HASH forge script script/ExecuteBatchPart.s.sol \
        --rpc-url $RPC_URL \
        --broadcast \
        --ffi \
        --slow
    
    # Check if execution was successful
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Part $part_num executed successfully!${NC}"
        return 0
    else
        echo -e "${RED}✗ Part $part_num failed!${NC}"
        return 1
    fi
}

# Execute all parts with delays
for i in $(seq 1 $NUM_PARTS); do
    execute_part $i
    
    # Check if execution failed
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}Execution failed at part $i. Stopping.${NC}"
        exit 1
    fi
    
    # Wait between parts (except after the last one)
    if [ $i -lt $NUM_PARTS ]; then
        echo -e "\n${YELLOW}⏱️  Waiting $DELAY_SECONDS seconds before next part...${NC}"
        sleep $DELAY_SECONDS
    fi
done

echo -e "\n${GREEN}=== ALL BATCH SWAP OPERATIONS COMPLETED SUCCESSFULLY! ===${NC}"
echo -e "Order Hash: ${BLUE}$ORDER_HASH${NC}"
echo -e "Total parts executed: ${GREEN}$NUM_PARTS${NC}" 