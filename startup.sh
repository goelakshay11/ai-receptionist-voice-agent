#!/bin/bash
# ============================================
# Naturals Salon AI Receptionist — Startup Script
# ============================================
# Starts everything with one command:
#   ./startup.sh
# ============================================

GREEN='\033[0;32m'
GOLD='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="goelakshay11/ai-receptionist-voice-agent"
WEBSITE_URL="https://goelakshay11.github.io/ai-receptionist-voice-agent/"

echo -e "${GOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║  Naturals Salon AI Receptionist      ║"
echo "  ║  Starting all services...            ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Check Docker ──
echo -e "${GREEN}[1/4] Docker${NC}"
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}  Docker is not running. Start Docker Desktop first.${NC}"
  exit 1
fi
echo "  Running."

# ── 2. n8n ──
echo -e "${GREEN}[2/4] n8n${NC}"
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
echo -e "${GREEN}[3/4] ngrok (n8n tunnel)${NC}"
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

# ── 4. Make website live (restore real index.html on gh-pages) ──
echo -e "${GREEN}[4/4] Website (going live)${NC}"
cd "$SCRIPT_DIR"
if command -v gh &> /dev/null && [ -f "website/index.html" ]; then
  git stash -q 2>/dev/null
  CURRENT_BRANCH=$(git branch --show-current)
  git checkout gh-pages -q 2>/dev/null
  if [ $? -eq 0 ]; then
    # Restore the real website from website/index.html (gh-pages has real keys)
    cp website/index.html index.html
    git add index.html
    # Only commit if there are changes
    git diff --cached --quiet 2>/dev/null
    if [ $? -ne 0 ]; then
      git commit -q -m "Make website live" 2>/dev/null
      GH_TOKEN=$(gh auth token 2>/dev/null)
      git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" 2>/dev/null
      git push origin gh-pages -q 2>/dev/null
      echo "  Website restored and live."
    else
      echo "  Already live: $WEBSITE_URL"
    fi
    git checkout "$CURRENT_BRANCH" -q 2>/dev/null
    git stash pop -q 2>/dev/null
  else
    echo "  Could not switch to gh-pages branch."
  fi
else
  echo "  gh CLI not found. Enable manually."
fi

# ── Summary ──
echo ""
echo -e "${GOLD}  ╔══════════════════════════════════════╗"
echo -e "  ║  ALL SERVICES RUNNING                ║"
echo -e "  ╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  n8n (local):  http://localhost:5678"
echo -e "  n8n (public): ${NGROK_URL:-not available}"
echo ""
echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║  WEBSITE: ${WEBSITE_URL}  ║${NC}"
echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  VAPI: https://dashboard.vapi.ai"
echo ""
if [ -n "$NGROK_URL" ]; then
  echo -e "  ${GOLD}IMPORTANT: If ngrok URL changed, update VAPI tool webhook URLs!${NC}"
fi
echo ""
echo -e "${GOLD}  Press Ctrl+C to stop ngrok${NC}"
echo -e "${GOLD}  Run ./stop.sh to stop everything including n8n + website${NC}"
echo ""

# Cleanup on exit
cleanup() {
  echo ""
  echo -e "${RED}Shutting down...${NC}"
  [ -n "$NGROK_PID" ] && kill $NGROK_PID 2>/dev/null
  echo "  ngrok stopped."
  echo "  n8n still running (use ./stop.sh to stop all)."
}
trap cleanup EXIT

wait
