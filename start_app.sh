#!/bin/bash
# ============================================
# COVID-19 Mortality Risk Calculator
# Unified Startup Script
# ============================================
# Purpose: Clean startup with process cleanup and health checks
# Usage: ./start_app.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_PORT=8000
VITE_PORT=5173
MAX_WAIT=60  # seconds to wait for API health

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "=============================================="
echo " COVID-19 Mortality Risk Calculator"
echo " Unified Startup Script"
echo "=============================================="
echo ""

# 1. Kill existing processes on our ports
echo -e "${YELLOW}[1/4] Cleaning up existing processes...${NC}"

# Kill processes on API port (macOS compatible)
if lsof -ti :$API_PORT > /dev/null 2>&1; then
    echo "   Killing process on port $API_PORT..."
    lsof -ti :$API_PORT | xargs kill -9 2>/dev/null || true
fi

# Kill processes on Vite port (and alternate 5174)
if lsof -ti :$VITE_PORT > /dev/null 2>&1; then
    echo "   Killing process on port $VITE_PORT..."
    lsof -ti :$VITE_PORT | xargs kill -9 2>/dev/null || true
fi

if lsof -ti :5174 > /dev/null 2>&1; then
    echo "   Killing process on port 5174..."
    lsof -ti :5174 | xargs kill -9 2>/dev/null || true
fi

sleep 1
echo -e "   ${GREEN}Ports $API_PORT, $VITE_PORT cleared.${NC}"

# 2. Start R Plumber API in background
echo ""
echo -e "${YELLOW}[2/4] Starting R Plumber API on port $API_PORT...${NC}"
cd "$PROJECT_DIR"

# Start R API in background, redirect output to log file
Rscript -e "library(plumber); pr('api.R') %>% pr_run(host='0.0.0.0', port=$API_PORT)" > api_server.log 2>&1 &
API_PID=$!
echo "   API started with PID: $API_PID"
echo "   Log file: api_server.log"

# 3. Wait for API health check
echo ""
echo -e "${YELLOW}[3/4] Waiting for API health check...${NC}"
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s "http://localhost:$API_PORT/health" > /dev/null 2>&1; then
        HEALTH_RESPONSE=$(curl -s "http://localhost:$API_PORT/health")
        echo -e "   ${GREEN}API healthy: $HEALTH_RESPONSE${NC}"
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        echo "   Still waiting... ($WAIT_COUNT seconds)"
    fi
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo -e "   ${RED}ERROR: API failed to start within $MAX_WAIT seconds${NC}"
    echo "   Check api_server.log for errors:"
    tail -20 api_server.log
    kill $API_PID 2>/dev/null || true
    exit 1
fi

# 4. Start Vite dev server
echo ""
echo -e "${YELLOW}[4/4] Starting Vite dev server on port $VITE_PORT...${NC}"
cd "$PROJECT_DIR/web-app"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "   Installing npm dependencies first..."
    npm install
fi

npm run dev &
VITE_PID=$!
echo "   Vite started with PID: $VITE_PID"

sleep 3

echo ""
echo "=============================================="
echo -e " ${GREEN}Application Started Successfully!${NC}"
echo "=============================================="
echo ""
echo " Frontend: http://localhost:$VITE_PORT"
echo " API:      http://localhost:$API_PORT"
echo " Health:   http://localhost:$API_PORT/health"
echo ""
echo " Process IDs:"
echo "   R API:  $API_PID"
echo "   Vite:   $VITE_PID"
echo ""
echo " To stop all processes:"
echo "   kill $API_PID $VITE_PID"
echo ""
echo " Or press Ctrl+C to stop this script"
echo "=============================================="
echo ""

# Trap to clean up on exit
cleanup() {
    echo ""
    echo "Shutting down..."
    kill $API_PID 2>/dev/null || true
    kill $VITE_PID 2>/dev/null || true
    echo "Done."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Keep script running to maintain child processes
wait
