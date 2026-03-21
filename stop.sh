#!/bin/bash
# ============================================
# Naturals Salon AI Receptionist — Stop Script
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}Stopping all services...${NC}"
echo ""

# 1. Stop website server
echo "[1/4] Stopping website server (port 4000)..."
pkill -f "http.server 4000" 2>/dev/null && echo "  Stopped." || echo "  Not running."

# 2. Stop Cloudflare Tunnel
echo "[2/4] Stopping Cloudflare Tunnel..."
pkill -f "cloudflared tunnel" 2>/dev/null && echo "  Stopped." || echo "  Not running."

# 3. Stop ngrok
echo "[3/4] Stopping ngrok..."
pkill -f ngrok 2>/dev/null && echo "  Stopped." || echo "  Not running."

# 4. Stop n8n Docker
echo "[4/4] Stopping n8n Docker containers..."
N8N_DIR="${N8N_DOCKER_DIR:-$HOME/N8N - self host local}"
if [ -d "$N8N_DIR" ]; then
  cd "$N8N_DIR"
  docker compose down 2>/dev/null && echo "  Stopped." || echo "  Not running or error."
else
  docker stop n8n n8n-postgres n8n-qdrant 2>/dev/null && echo "  Stopped containers." || echo "  Not running."
fi

echo ""
echo -e "${GREEN}All services stopped.${NC}"
