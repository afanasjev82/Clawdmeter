#!/bin/bash

# Start script for the Clawdmeter BLE daemon (Docker).
#
# BLE only works on a native Linux host (host networking + host BlueZ over
# D-Bus). On Docker Desktop (Windows/macOS) the daemon cannot reach the device.

set -e
cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ENV_FILE=".env"
DETACHED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--detach)
            DETACHED=true
            shift
            ;;
        -e|--env)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --detach     Run in the background (detached)"
            echo "  -e, --env FILE   Use specified env file (default: .env)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# BLE-in-Docker only works on Linux.
if [ "$(uname -s)" != "Linux" ]; then
    echo -e "${YELLOW}⚠️  Not a Linux host — Docker can't reach the Bluetooth radio here.${NC}"
    echo -e "${YELLOW}   The container will start but the daemon won't connect to the device.${NC}"
    echo -e "${YELLOW}   Deploy this on your Ubuntu server.${NC}"
fi

# Seed .env from the example on first run (optional file).
if [ ! -f "$ENV_FILE" ] && [ -f ".env.example" ]; then
    echo -e "${YELLOW}💡 $ENV_FILE not found — creating it from .env.example${NC}"
    cp .env.example "$ENV_FILE"
fi

# Best-effort host checks (warn, don't block).
if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet bluetooth 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Host bluetooth.service is not active — start it with: sudo systemctl start bluetooth${NC}"
    fi
fi

CRED_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ ! -f "$CRED_DIR/.credentials.json" ]; then
    echo -e "${YELLOW}⚠️  No token at $CRED_DIR/.credentials.json — run 'claude login' on this host first.${NC}"
fi

# Pass --env-file only if it exists (compose auto-reads .env otherwise).
COMPOSE_ARGS=()
[ -f "$ENV_FILE" ] && COMPOSE_ARGS+=(--env-file "$ENV_FILE")

echo -e "${GREEN}🚀 Starting Clawdmeter daemon...${NC}"
echo -e "🔑 Token dir: ${YELLOW}$CRED_DIR${NC}"

if [ "$DETACHED" = true ]; then
    echo -e "${GREEN}✅ Starting detached...${NC}"
    docker compose "${COMPOSE_ARGS[@]}" up -d --build --remove-orphans
    echo -e "${GREEN}✅ Up. Logs: ${NC}docker compose logs -f"
else
    echo -e "${GREEN}✅ Starting in foreground (Ctrl+C to stop)...${NC}"
    docker compose "${COMPOSE_ARGS[@]}" up --build --remove-orphans
fi
