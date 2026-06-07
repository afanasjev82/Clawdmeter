#!/bin/bash

# Start the Clawdmeter stack (token-refresher + a transport) via Docker Compose.
# Linux host. Transports:
#   -t ble : Bluetooth LE      (needs a host BT adapter + BlueZ)
#   -t usb : the device's USB cable (no Bluetooth)

set -e
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENV_FILE=".env"
DETACHED=false
TRANSPORT="ble"

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--detach)    DETACHED=true; shift ;;
        -e|--env)       ENV_FILE="$2"; shift 2 ;;
        -t|--transport) TRANSPORT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -t, --transport ble|usb  How to reach the device (default: ble)"
            echo "                           ble = Bluetooth LE; usb = USB serial cable"
            echo "  -d, --detach             Run in the background (24/7)"
            echo "  -e, --env FILE           Use specified env file (default: .env)"
            echo "  -h, --help               Show this help message"
            exit 0 ;;
        *) echo -e "${RED}❌ Unknown option: $1${NC}"; exit 1 ;;
    esac
done

if [ "$TRANSPORT" != "ble" ] && [ "$TRANSPORT" != "usb" ]; then
    echo -e "${RED}❌ --transport must be 'ble' or 'usb' (got '$TRANSPORT')${NC}"; exit 1
fi

# Seed .env from the example on first run, then load it.
if [ ! -f "$ENV_FILE" ] && [ -f ".env.example" ]; then
    echo -e "${YELLOW}💡 $ENV_FILE not found — creating it from .env.example${NC}"
    cp .env.example "$ENV_FILE"
fi
if [ -f "$ENV_FILE" ]; then
    set -a; # shellcheck disable=SC1090
    source "$ENV_FILE"; set +a
fi
SEED="${CLAUDE_CREDENTIALS_FILE:-./secrets/.credentials.json}"

# The seed credentials must exist (a missing bind-mount source becomes a dir).
if [ ! -f "$SEED" ]; then
    echo -e "${RED}❌ Seed credentials not found: $SEED${NC}"
    echo -e "${YELLOW}💡 Copy your Claude token there once:${NC}"
    echo -e "   mkdir -p \"$(dirname "$SEED")\" && cp ~/.claude/.credentials.json \"$SEED\""
    exit 1
fi

# Transport-specific preflight (warn, don't block).
if [ "$TRANSPORT" = "usb" ]; then
    PORT="${SERIAL_PORT:-/dev/ttyUSB0}"
    if [ ! -e "$PORT" ]; then
        echo -e "${YELLOW}⚠️  Serial port $PORT not found — is the device's USB cable plugged into this host?${NC}"
    else
        echo -e "🔌 Serial port: ${YELLOW}$PORT${NC}"
    fi
else
    if [ "$(uname -s)" != "Linux" ]; then
        echo -e "${YELLOW}⚠️  Not Linux — Docker can't reach the Bluetooth radio. Deploy on Linux or use -t usb.${NC}"
    fi
    if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet bluetooth 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Host bluetooth.service not active — sudo systemctl enable --now bluetooth${NC}"
    fi
fi

COMPOSE_ARGS=()
[ -f "$ENV_FILE" ] && COMPOSE_ARGS+=(--env-file "$ENV_FILE")

echo -e "${GREEN}🚀 Starting Clawdmeter (transport: ${TRANSPORT})...${NC}"

if [ "$DETACHED" = true ]; then
    docker compose "${COMPOSE_ARGS[@]}" --profile "$TRANSPORT" up -d --build --remove-orphans
    echo -e "${GREEN}✅ Up.${NC} Logs: ${YELLOW}docker compose logs -f${NC}"
else
    docker compose "${COMPOSE_ARGS[@]}" --profile "$TRANSPORT" up --build --remove-orphans
fi
