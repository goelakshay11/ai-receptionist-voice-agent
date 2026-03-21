#!/bin/bash
# ============================================
# Naturals Salon AI Receptionist — Startup Script
# ============================================
# This script starts all required services:
# 1. n8n (Docker) — workflow engine
# 2. ngrok — tunnel for n8n API
# 3. Website — local HTTP server
# 4. Cloudflare Tunnel — public URL for website
# ============================================

set -e

GREEN='\033[0;32m'
GOLD='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GOLD}========================================${NC}"
echo -e "${GOLD}  Naturals Salon AI Receptionist${NC}"
echo -e "${GOLD}  Starting all services...${NC}"
echo -e "${GOLD}========================================${NC}"
echo ""

# ── 1. Check Docker ──
echo -e "${GREEN}[1/5] Checking Docker...${NC}"
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}Docker is not running. Please start Docker Desktop first.${NC}"
  exit 1
fi
echo "  Docker is running."
echo ""

# ── 2. Start n8n (Docker Compose) ──
echo -e "${GREEN}[2/5] Starting n8n...${NC}"
N8N_DIR="${N8N_DOCKER_DIR:-$HOME/N8N - self host local}"
if [ -d "$N8N_DIR" ]; then
  cd "$N8N_DIR"
  docker compose up -d 2>/dev/null
  echo "  n8n started at http://localhost:5678"
else
  if docker ps | grep -q n8n; then
    echo "  n8n container is already running."
  else
    echo -e "${RED}  n8n not found. Set N8N_DOCKER_DIR in .env${NC}"
  fi
fi
echo ""

# ── 3. Start ngrok tunnel for n8n ──
echo -e "${GREEN}[3/5] Starting ngrok tunnel for n8n (port 5678)...${NC}"
if command -v ngrok &> /dev/null; then
  ngrok http 5678 --log=stdout > /tmp/ngrok-n8n.log 2>&1 &
  NGROK_PID=$!
  sleep 4
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*' | head -1 | cut -d'"' -f4)
  if [ -n "$NGROK_URL" ]; then
    echo "  ngrok tunnel: $NGROK_URL"
    echo -e "  ${GOLD}IMPORTANT: Update VAPI tool webhook URLs if ngrok URL changed!${NC}"
  else
    echo "  ngrok started but URL not detected. Check http://localhost:4040"
  fi
else
  NGROK_PID=""
  echo -e "${RED}  ngrok not installed. Install: brew install ngrok${NC}"
fi
echo ""

# ── 4. Start website server ──
echo -e "${GREEN}[4/5] Starting website (port 4000)...${NC}"
cd "$SCRIPT_DIR/website"
python3 -m http.server 4000 > /tmp/website-server.log 2>&1 &
WEBSITE_PID=$!
echo "  Website running at http://localhost:4000"
echo ""

# ── 5. Start Cloudflare Tunnel for website ──
echo -e "${GREEN}[5/5] Starting Cloudflare Tunnel for website (port 4000)...${NC}"
CF_PID=""
CF_URL=""
if command -v cloudflared &> /dev/null; then
  cloudflared tunnel --url http://localhost:4000 > /tmp/cloudflared-website.log 2>&1 &
  CF_PID=$!
  sleep 6
  CF_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared-website.log 2>/dev/null | head -1)
  if [ -n "$CF_URL" ]; then
    echo "  Cloudflare tunnel: $CF_URL"
  else
    echo "  Cloudflare tunnel started but URL not detected."
    echo "  Check: cat /tmp/cloudflared-website.log"
  fi
else
  echo -e "${RED}  cloudflared not installed. Install: brew install cloudflared${NC}"
fi
echo ""

# ── Summary ──
echo -e "${GOLD}========================================${NC}"
echo -e "${GOLD}  All services started!${NC}"
echo -e "${GOLD}========================================${NC}"
echo ""
echo "  n8n (local):    http://localhost:5678"
echo "  n8n (public):   ${NGROK_URL:-not available}"
echo "  Website (local): http://localhost:4000"
echo "  Website (public): ${CF_URL:-not available}"
echo ""
echo "  VAPI Dashboard:  https://dashboard.vapi.ai"
echo ""
echo -e "${GOLD}  Press Ctrl+C to stop all services${NC}"
echo ""

# Cleanup on exit
cleanup() {
  echo ""
  echo -e "${RED}Shutting down...${NC}"
  [ -n "$WEBSITE_PID" ] && kill $WEBSITE_PID 2>/dev/null && echo "  Website stopped."
  [ -n "$NGROK_PID" ] && kill $NGROK_PID 2>/dev/null && echo "  ngrok stopped."
  [ -n "$CF_PID" ] && kill $CF_PID 2>/dev/null && echo "  Cloudflare tunnel stopped."
  echo "  n8n Docker containers still running (stop with: ./stop.sh)"
}
trap cleanup EXIT

wait
