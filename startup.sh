#!/bin/bash
# ============================================
# Naturals Salon AI Receptionist — Startup Script
# ============================================
# Starts all services with one command:
#   ./startup.sh
# ============================================

GREEN='\033[0;32m'
GOLD='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║  Naturals Salon AI Receptionist      ║"
echo "  ║  Starting all services...            ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── Kill any existing services first ──
pkill -f "http.server 4000" 2>/dev/null
pkill -f "cloudflared tunnel" 2>/dev/null
sleep 1

# ── 1. Check Docker ──
echo -e "${GREEN}[1/5] Docker${NC}"
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}  Docker is not running. Start Docker Desktop first.${NC}"
  exit 1
fi
echo "  Running."

# ── 2. n8n ──
echo -e "${GREEN}[2/5] n8n${NC}"
if docker ps 2>/dev/null | grep -q n8n; then
  echo "  Already running."
else
  N8N_DIR="${N8N_DOCKER_DIR:-$HOME/N8N - self host local}"
  if [ -d "$N8N_DIR" ]; then
    cd "$N8N_DIR" && docker compose up -d 2>/dev/null
    echo "  Started."
  else
    echo -e "${RED}  Not found. Set N8N_DOCKER_DIR in .env${NC}"
  fi
fi

# ── 3. ngrok ──
echo -e "${GREEN}[3/5] ngrok (n8n tunnel)${NC}"
NGROK_PID=""
NGROK_URL=""
if pgrep -f "ngrok http" > /dev/null 2>&1; then
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*' | head -1 | cut -d'"' -f4)
  echo "  Already running: $NGROK_URL"
elif command -v ngrok &> /dev/null; then
  ngrok http 5678 --log=stdout > /tmp/ngrok-n8n.log 2>&1 &
  NGROK_PID=$!
  sleep 4
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*' | head -1 | cut -d'"' -f4)
  echo "  Started: ${NGROK_URL:-check http://localhost:4040}"
else
  echo -e "${RED}  Not installed. Run: brew install ngrok${NC}"
fi

# ── 4. Website ──
echo -e "${GREEN}[4/5] Website (port 4000)${NC}"
cd "$SCRIPT_DIR/website"
python3 -m http.server 4000 > /dev/null 2>&1 &
WEBSITE_PID=$!
sleep 1
if curl -s -o /dev/null -w "" http://localhost:4000/ 2>/dev/null; then
  echo "  Running: http://localhost:4000"
else
  echo -e "${RED}  Failed to start.${NC}"
fi

# ── 5. Cloudflare Tunnel ──
echo -e "${GREEN}[5/5] Cloudflare Tunnel (website)${NC}"
CF_PID=""
CF_URL=""
if command -v cloudflared &> /dev/null; then
  # cloudflared writes URL to stderr
  cloudflared tunnel --url http://localhost:4000 2>/tmp/cf-startup.log &
  CF_PID=$!

  # Wait and poll for the URL (up to 15 seconds)
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    CF_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cf-startup.log 2>/dev/null | head -1)
    if [ -n "$CF_URL" ]; then
      break
    fi
    sleep 1
  done

  if [ -n "$CF_URL" ]; then
    echo "  Started: $CF_URL"
  else
    echo "  Started but URL not detected yet."
    echo "  Run: grep trycloudflare /tmp/cf-startup.log"
  fi
else
  echo -e "${RED}  Not installed. Run: brew install cloudflared${NC}"
fi

# ── Summary ──
echo ""
echo -e "${GOLD}  ╔══════════════════════════════════════╗"
echo -e "  ║  ALL SERVICES RUNNING                ║"
echo -e "  ╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  n8n:      http://localhost:5678"
echo -e "  n8n URL:  ${NGROK_URL:-not available}"
echo -e "  Website:  http://localhost:4000"
echo ""
if [ -n "$CF_URL" ]; then
  echo -e "  ${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${CYAN}║  WEBSITE PUBLIC URL:                                ║${NC}"
  echo -e "  ${CYAN}║  $CF_URL  ║${NC}"
  echo -e "  ${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
else
  echo -e "  ${RED}Website public URL not available.${NC}"
fi
echo ""
echo -e "  VAPI:     https://dashboard.vapi.ai"
echo ""
echo -e "${GOLD}  Press Ctrl+C to stop website + tunnels${NC}"
echo -e "${GOLD}  Run ./stop.sh to stop everything including n8n${NC}"
echo ""

# Cleanup on exit
cleanup() {
  echo ""
  echo -e "${RED}Shutting down...${NC}"
  [ -n "$WEBSITE_PID" ] && kill $WEBSITE_PID 2>/dev/null
  [ -n "$NGROK_PID" ] && kill $NGROK_PID 2>/dev/null
  [ -n "$CF_PID" ] && kill $CF_PID 2>/dev/null
  echo "  Website, ngrok, cloudflared stopped."
  echo "  n8n still running (use ./stop.sh to stop all)."
}
trap cleanup EXIT

wait
