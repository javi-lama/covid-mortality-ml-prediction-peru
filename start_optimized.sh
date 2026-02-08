#!/bin/bash
# ============================================
# COVID-19 Mortality Risk Calculator
# OPTIMIZED Startup Script (Fast API)
# ============================================
#
# PERFORMANCE: Startup in ~5 seconds (vs 5-10 minutes original)
#
# PREREQUISITES: Run build_artifacts.R first to generate .rds files
#   Rscript build_artifacts.R
#
# Usage: ./start_optimized.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_PORT=8000
VITE_PORT=5173
MAX_WAIT=15  # Reduced from 60s - optimized API starts in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=============================================="
echo " COVID-19 Mortality Risk Calculator"
echo " OPTIMIZED API (Fast Startup)"
echo "==============================================${NC}"
echo ""

# 0. Check if optimized artifacts exist
echo -e "${YELLOW}[0/4] Checking optimized artifacts...${NC}"
cd "$PROJECT_DIR"

REQUIRED_FILES=("final_workflow_optimized.rds" "explainer_optimized.rds" "patient_template.rds" "df_training_cached.rds")
MISSING=0

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "   ${RED}Missing: $file${NC}"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}Building artifacts first (one-time setup)...${NC}"
    Rscript r/build_artifacts.R
    echo ""
fi

echo -e "   ${GREEN}All artifacts ready.${NC}"

# 1. Kill existing processes on our ports
echo ""
echo -e "${YELLOW}[1/4] Cleaning up existing processes...${NC}"

if lsof -ti :$API_PORT > /dev/null 2>&1; then
    echo "   Killing process on port $API_PORT..."
    lsof -ti :$API_PORT | xargs kill -9 2>/dev/null || true
fi

if lsof -ti :$VITE_PORT > /dev/null 2>&1; then
    echo "   Killing process on port $VITE_PORT..."
    lsof -ti :$VITE_PORT | xargs kill -9 2>/dev/null || true
fi

if lsof -ti :5174 > /dev/null 2>&1; then
    lsof -ti :5174 | xargs kill -9 2>/dev/null || true
fi

sleep 1
echo -e "   ${GREEN}Ports cleared.${NC}"

# 2. Start OPTIMIZED R Plumber API in background
echo ""
echo -e "${YELLOW}[2/4] Starting OPTIMIZED R API on port $API_PORT...${NC}"
cd "$PROJECT_DIR"

# Use api_optimized.R for fast startup
Rscript -e "library(plumber); pr('r/api_optimized.R') %>% pr_run(host='0.0.0.0', port=$API_PORT)" > api_server.log 2>&1 &
API_PID=$!
echo "   API started with PID: $API_PID"

# 3. Wait for API health check (should be fast now!)
echo ""
echo -e "${YELLOW}[3/4] Waiting for API health check...${NC}"
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s "http://localhost:$API_PORT/health" > /dev/null 2>&1; then
        HEALTH_RESPONSE=$(curl -s "http://localhost:$API_PORT/health")
        echo -e "   ${GREEN}API healthy in ${WAIT_COUNT}s!${NC}"
        echo "   $HEALTH_RESPONSE"
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
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
echo -e "${YELLOW}[4/4] Starting Vite dev server...${NC}"
cd "$PROJECT_DIR/web-app"

if [ ! -d "node_modules" ]; then
    echo "   Installing npm dependencies..."
    npm install
fi

npm run dev &
VITE_PID=$!
echo "   Vite started with PID: $VITE_PID"

sleep 2

echo ""
echo -e "${GREEN}=============================================="
echo " Application Started Successfully!"
echo "==============================================${NC}"
echo ""
echo -e " ${CYAN}Frontend:${NC} http://localhost:$VITE_PORT"
echo -e " ${CYAN}API:${NC}      http://localhost:$API_PORT"
echo -e " ${CYAN}Health:${NC}   http://localhost:$API_PORT/health"
echo ""
echo " Process IDs: API=$API_PID, Vite=$VITE_PID"
echo ""
echo -e " ${YELLOW}Performance:${NC}"
echo "   - API startup: ~0.1 seconds"
echo "   - Prediction: ~6-10 seconds (includes SHAP)"
echo ""
echo " Press Ctrl+C to stop"
echo "=============================================="
echo ""

cleanup() {
    echo ""
    echo "Shutting down..."
    kill $API_PID 2>/dev/null || true
    kill $VITE_PID 2>/dev/null || true
    echo "Done."
    exit 0
}

trap cleanup SIGINT SIGTERM

wait
