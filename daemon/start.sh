#!/bin/bash

# Start the Clawdmeter stack (token-refresher + BLE daemon) via Docker Compose.
# Linux host only — BLE needs the host's BlueZ over D-Bus.

set -e
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENV_FILE=".env"
DETACHED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--detach) DETACHED=true; shift ;;
        -e|--env)    ENV_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --detach     Run in the background (24/7)"
            echo "  -e, --env FILE   Use specified env file (default: .env)"
            echo "  -h, --help       Show this help message"
            exit 0 ;;
        *) echo -e "${RED}❌ Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# Seed .env from the example on first run.
if [ ! -f "$ENV_FILE" ] && [ -f ".env.example" ]; then
    echo -e "${YELLOW}💡 $ENV_FILE not found — creating it from .env.example${NC}"
    cp .env.example "$ENV_FILE"
fi
# Load it so we know where the seed credentials live.
if [ -f "$ENV_FILE" ]; then
    set -a; # shellcheck disable=SC1090
    source "$ENV_FILE"; set +a
fi
SEED="${CLAUDE_CREDENTIALS_FILE:-./secrets/.credentials.json}"

# BLE only works on Linux.
if [ "$(uname -s)" != "Linux" ]; then
    echo -e "${YELLOW}⚠️  Not a Linux host — Docker can't reach the Bluetooth radio here.${NC}"
    echo -e "${YELLOW}   The stack will build/start but the daemon won't connect. Deploy on Linux.${NC}"
fi

# The seed credentials must exist, or Docker would bind-mount a missing file as
# an empty directory and the refresher couldn't read it.
if [ ! -f "$SEED" ]; then
    echo -e "${RED}❌ Seed credentials not found: $SEED${NC}"
    echo -e "${YELLOW}💡 Copy your Claude token there once (from a machine where you ran 'claude login'):${NC}"
    echo -e "   mkdir -p \"$(dirname "$SEED")\" && cp ~/.claude/.credentials.json \"$SEED\""
    exit 1
fi

# Best-effort host BlueZ check (warn, don't block).
if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet bluetooth 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Host bluetooth.service is not active — sudo systemctl enable --now bluetooth${NC}"
    fi
fi

COMPOSE_ARGS=()
[ -f "$ENV_FILE" ] && COMPOSE_ARGS+=(--env-file "$ENV_FILE")

echo -e "${GREEN}🚀 Starting Clawdmeter (refresher + daemon)...${NC}"
echo -e "🔑 Seed credentials: ${YELLOW}$SEED${NC}"

if [ "$DETACHED" = true ]; then
    echo -e "${GREEN}✅ Starting detached...${NC}"
    docker compose "${COMPOSE_ARGS[@]}" up -d --build --remove-orphans
    echo -e "${GREEN}✅ Up.${NC} Logs: ${YELLOW}docker compose logs -f${NC}"
else
    echo -e "${GREEN}✅ Starting in foreground (Ctrl+C to stop)...${NC}"
    docker compose "${COMPOSE_ARGS[@]}" up --build --remove-orphans
fi
