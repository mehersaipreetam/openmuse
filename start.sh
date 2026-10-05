#!/usr/bin/env bash
set -e

# Change to the project directory
cd "$(dirname "$0")"

# Colors for terminal output
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}"
echo "=========================================================="
echo "               🌟 Starting OpenMuse Pipeline              "
echo "=========================================================="
echo -e "${RESET}"

mkdir -p .openmuse/logs .openmuse/bin

# 1. Clean up any stale processes occupying ports 8787, 8790, 8081
kill_port() {
  local port=$1
  local pids=$(lsof -ti tcp:$port 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo -e "${YELLOW}Cleaning up stale process on port $port...${RESET}"
    kill -9 $pids 2>/dev/null || true
    sleep 1
  fi
}

kill_port 8790
kill_port 8787
kill_port 8081
pkill -f "cloudflared tunnel" 2>/dev/null || true

# 2. Graceful shutdown handler
cleanup() {
  echo -e "\n${YELLOW}Shutting down OpenMuse services...${RESET}"
  [ -n "$KEEPALIVE_PID" ] && kill "$KEEPALIVE_PID" 2>/dev/null || true
  [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null || true
  [ -n "$WORKER_PID" ] && kill "$WORKER_PID" 2>/dev/null || true
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  [ -n "$WEB_PID" ] && kill "$WEB_PID" 2>/dev/null || true
  pkill -f "cloudflared tunnel" 2>/dev/null || true
  pkill -P $$ 2>/dev/null || true
  echo -e "${GREEN}All services stopped cleanly.${RESET}"
  exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 3. Ensure cloudflared binary exists
if [ ! -f .openmuse/bin/cloudflared ]; then
  echo -n "Downloading cloudflared binary... "
  curl -sSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o .openmuse/bin/cloudflared
  chmod +x .openmuse/bin/cloudflared
  echo -e "${GREEN}${BOLD}DONE${RESET}"
fi

# 4. Start Browser Worker (port 8790)
echo -n "Starting Browser Worker (Port 8790)... "
node --env-file=.env --import tsx apps/worker/src/index.ts > .openmuse/logs/worker.log 2>&1 &
WORKER_PID=$!

for i in {1..20}; do
  if curl -s http://127.0.0.1:8790/status >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
echo -e "${GREEN}${BOLD}READY${RESET}"

# 5. Start OpenMuse API Server (port 8787)
echo -n "Starting OpenMuse API Server (Port 8787)... "
node --env-file=.env --import tsx apps/server/src/index.ts > .openmuse/logs/server.log 2>&1 &
SERVER_PID=$!

for i in {1..30}; do
  if curl -s http://127.0.0.1:8787/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
echo -e "${GREEN}${BOLD}READY${RESET}"

# 6. Start Web Client (port 8081)
echo -n "Starting Web Client (Port 8081)... "
pnpm --dir apps/mobile web > .openmuse/logs/web.log 2>&1 &
WEB_PID=$!

for i in {1..30}; do
  if curl -s http://127.0.0.1:8081/ >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
echo -e "${GREEN}${BOLD}READY${RESET}"

# 7. Start Cloudflare Tunnel
echo -n "Starting Cloudflare Public Tunnel... "
.openmuse/bin/cloudflared tunnel --edge-ip-version 4 --protocol http2 --url http://127.0.0.1:8787 > .openmuse/logs/tunnel.log 2>&1 &
TUNNEL_PID=$!

TUNNEL_URL=""
for i in {1..25}; do
  TUNNEL_URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" .openmuse/logs/tunnel.log 2>/dev/null | head -n 1 || true)
  if [ -n "$TUNNEL_URL" ]; then
    break
  fi
  sleep 1
done

if [ -n "$TUNNEL_URL" ]; then
  echo -e "${GREEN}${BOLD}CONNECTED${RESET}"
  echo "$TUNNEL_URL" > .openmuse/tunnel-url.txt
  
  # Start keep-alive ping in background to prevent router NAT timeout
  (
    while true; do
      sleep 20
      curl -s -m 5 "$TUNNEL_URL/api/health" >/dev/null 2>&1 || true
    done
  ) &
  KEEPALIVE_PID=$!
else
  echo -e "${YELLOW}WAITING (Will continue in background)${RESET}"
fi

echo -e "\n${BOLD}${GREEN}==========================================================${RESET}"
echo -e "${BOLD}${GREEN}               🚀 OpenMuse is LIVE & READY!               ${RESET}"
echo -e "${BOLD}${GREEN}==========================================================${RESET}"
if [ -n "$TUNNEL_URL" ]; then
  echo -e "🌍 ${BOLD}Public Tunnel:${RESET}   ${CYAN}${TUNNEL_URL}${RESET}"
  echo -e "📦 ${BOLD}APK Download:${RESET}    ${CYAN}${TUNNEL_URL}/openmuse.apk${RESET}"
  echo -e "🌐 ${BOLD}Local Web:${RESET}       ${CYAN}http://localhost:8081${RESET}"
  echo -e "⚡ ${BOLD}Local Server:${RESET}    ${CYAN}http://localhost:8787${RESET}"
  echo -e "\n📱 ${BOLD}SCAN WITH PHONE CAMERA TO CONNECT:${RESET}"
  python3 -c "
import qrcode, sys
url = '${TUNNEL_URL}'
qr = qrcode.QRCode()
qr.add_data(url)
qr.print_ascii(invert=True)
" 2>/dev/null || echo -e "  Visit: ${TUNNEL_URL}"
else
  echo -e "🌐 ${BOLD}Local Web:${RESET}       ${CYAN}http://localhost:8081${RESET}"
  echo -e "⚡ ${BOLD}Local Server:${RESET}    ${CYAN}http://localhost:8787${RESET}"
fi
echo -e "${BOLD}==========================================================${RESET}"
echo -e "${YELLOW}Streaming logs below. Press Ctrl+C anytime to stop.${RESET}\n"

# 8. Stream combined logs to terminal
tail -n 0 -f .openmuse/logs/server.log .openmuse/logs/worker.log
