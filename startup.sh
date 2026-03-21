#!/bin/bash
# ============================================
# Naturals Salon AI Receptionist — Startup Script
# ============================================
# This script starts all required services:
# 1. n8n (Docker) — workflow engine
# 2. ngrok — tunnel for n8n
# 3. Website — local HTTP server
# ============================================

set -e

# Colors
GREEN='\033[0;32m'
GOLD='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GOLD}========================================${NC}"
echo -e "${GOLD}  Naturals Salon AI Receptionist${NC}"
echo -e "${GOLD}  Starting all services...${NC}"
echo -e "${GOLD}========================================${NC}"
echo ""

# ── 1. Check Docker is running ──
echo -e "${GREEN}[1/4] Checking Docker...${NC}"
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}Docker is not running. Please start Docker Desktop first.${NC}"
  exit 1
fi
echo "  Docker is running."

# ── 2. Start n8n (Docker Compose) ──
echo -e "${GREEN}[2/4] Starting n8n...${NC}"
N8N_DIR="${N8N_DOCKER_DIR:-$HOME/N8N - self host local}"
if [ -d "$N8N_DIR" ]; then
  cd "$N8N_DIR"
  docker compose up -d
  echo "  n8n started at http://localhost:5678"
else
  echo "  n8n Docker directory not found at: $N8N_DIR"
  echo "  Set N8N_DOCKER_DIR in .env if it's in a different location."
  echo "  Checking if n8n container is already running..."
  if docker ps | grep -q n8n; then
    echo "  n8n container is already running."
  else
    echo -e "${RED}  n8n is not running. Please start it manually.${NC}"
  fi
fi
echo ""

# ── 3. Start ngrok tunnel for n8n ──
echo -e "${GREEN}[3/4] Starting ngrok tunnel...${NC}"
echo "  Note: If you have a persistent ngrok domain, use:"
echo "  ngrok http 5678 --domain=your-domain.ngrok-free.dev"
echo ""
echo "  Starting ngrok in background..."
ngrok http 5678 --log=stdout > /tmp/ngrok-n8n.log 2>&1 &
NGROK_PID=$!
sleep 3

# Extract the ngrok URL
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*' | head -1 | cut -d'"' -f4)
if [ -n "$NGROK_URL" ]; then
  echo "  ngrok tunnel: $NGROK_URL"
  echo ""
  echo -e "${GOLD}  IMPORTANT: Update your VAPI tool webhook URLs${NC}"
  echo -e "${GOLD}  if the ngrok URL has changed!${NC}"
else
  echo "  Could not detect ngrok URL. Check http://localhost:4040"
fi
echo ""

# ── 4. Start website server ──
echo -e "${GREEN}[4/4] Starting website...${NC}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/website"
python3 -m http.server 4000 &
WEBSITE_PID=$!
echo "  Website running at http://localhost:4000"
echo ""

# ── Summary ──
echo -e "${GOLD}========================================${NC}"
echo -e "${GOLD}  All services started!${NC}"
echo -e "${GOLD}========================================${NC}"
echo ""
echo "  n8n:     http://localhost:5678"
echo "  ngrok:   ${NGROK_URL:-http://localhost:4040}"
echo "  Website: http://localhost:4000"
echo ""
echo "  VAPI Dashboard: https://dashboard.vapi.ai"
echo ""
echo -e "${GOLD}  Press Ctrl+C to stop all services${NC}"
echo ""

# Cleanup on exit
cleanup() {
  echo ""
  echo -e "${RED}Shutting down...${NC}"
  kill $WEBSITE_PID 2>/dev/null
  kill $NGROK_PID 2>/dev/null
  echo "  Website and ngrok stopped."
  echo "  n8n Docker containers are still running (stop with: docker compose down)"
}
trap cleanup EXIT

# Keep running
wait
