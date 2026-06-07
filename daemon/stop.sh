#!/bin/bash

# Stop the Clawdmeter stack (Docker Compose). Linux host.

set -e
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENV_FILE=".env"
REMOVE_IMAGE=false
REMOVE_VOLUMES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)     ENV_FILE="$2"; shift 2 ;;
        --rmi)        REMOVE_IMAGE=true; shift ;;
        -v|--volumes) REMOVE_VOLUMES=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -e, --env FILE   Use specified env file (default: .env)"
            echo "  --rmi            Also remove the built image"
            echo "  -v, --volumes    Also remove volumes (drops the cached/refreshed token!)"
            echo "  -h, --help       Show this help message"
            exit 0 ;;
        *) echo -e "${RED}❌ Unknown option: $1${NC}"; exit 1 ;;
    esac
done

COMPOSE_ARGS=()
[ -f "$ENV_FILE" ] && COMPOSE_ARGS+=(--env-file "$ENV_FILE")
# Activate both transport profiles so `down` tears down whichever is running.
COMPOSE_ARGS+=(--profile ble --profile usb)

DOWN=(down --remove-orphans)
[ "$REMOVE_IMAGE" = true ]   && DOWN+=(--rmi local)
[ "$REMOVE_VOLUMES" = true ] && DOWN+=(-v)

if [ "$REMOVE_VOLUMES" = true ]; then
    echo -e "${YELLOW}⚠️  Removing volumes — the refreshed token cache will be wiped;${NC}"
    echo -e "${YELLOW}   the next start re-seeds from your secrets file.${NC}"
fi

echo -e "${GREEN}🛑 Stopping Clawdmeter...${NC}"
docker compose "${COMPOSE_ARGS[@]}" "${DOWN[@]}"
echo -e "${GREEN}✅ Stopped${NC}"
