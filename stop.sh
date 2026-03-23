#!/bin/bash
# ============================================
# Naturals Salon AI Receptionist — Stop Script
# ============================================
# Stops everything with one command:
#   ./stop.sh
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="goelakshay11/ai-receptionist-voice-agent"

echo -e "${RED}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║  Stopping all services...            ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# 1. Stop ngrok
echo -e "${RED}[1/3] ngrok${NC}"
pkill -f ngrok 2>/dev/null && echo "  Stopped." || echo "  Not running."

# 2. Stop n8n Docker
echo -e "${RED}[2/3] n8n Docker${NC}"
N8N_DIR="${N8N_DOCKER_DIR:-$HOME/N8N - self host local}"
if [ -d "$N8N_DIR" ]; then
  cd "$N8N_DIR"
  docker compose down 2>/dev/null && echo "  Stopped." || echo "  Not running or error."
else
  docker stop n8n n8n-postgres n8n-qdrant 2>/dev/null && echo "  Stopped." || echo "  Not running."
fi

# 3. Take website offline (push maintenance page to gh-pages)
echo -e "${RED}[3/3] Website (taking offline)${NC}"
cd "$SCRIPT_DIR"
if command -v gh &> /dev/null && [ -f "website/maintenance.html" ]; then
  git stash -q 2>/dev/null
  CURRENT_BRANCH=$(git branch --show-current)
  git checkout gh-pages -q 2>/dev/null
  if [ $? -eq 0 ]; then
    cp website/maintenance.html index.html
    git add index.html
    git commit -q -m "Take website offline (maintenance mode)" 2>/dev/null
    GH_TOKEN=$(gh auth token 2>/dev/null)
    git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" 2>/dev/null
    git push origin gh-pages -q 2>/dev/null
    echo "  Website set to maintenance mode."
    git checkout "$CURRENT_BRANCH" -q 2>/dev/null
    git stash pop -q 2>/dev/null
  else
    echo "  Could not switch to gh-pages branch."
  fi
else
  echo "  gh CLI not found or maintenance.html missing."
  echo "  Take offline manually: push maintenance.html as index.html to gh-pages"
fi

echo ""
echo -e "${GREEN}  ╔══════════════════════════════════════╗"
echo -e "  ║  ALL SERVICES STOPPED                ║"
echo -e "  ╚══════════════════════════════════════╝${NC}"
echo ""
echo "  To restart: ./startup.sh"
