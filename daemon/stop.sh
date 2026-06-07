#!/bin/bash

# Stop script for the Clawdmeter BLE daemon (Docker).

set -e
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENV_FILE=".env"
REMOVE_IMAGE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV_FILE="$2"
            shift 2
            ;;
        --rmi)
            REMOVE_IMAGE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -e, --env FILE   Use specified env file (default: .env)"
            echo "  --rmi            Also remove the built image"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

COMPOSE_ARGS=()
[ -f "$ENV_FILE" ] && COMPOSE_ARGS+=(--env-file "$ENV_FILE")

echo -e "${GREEN}🛑 Stopping Clawdmeter daemon...${NC}"
if [ "$REMOVE_IMAGE" = true ]; then
    docker compose "${COMPOSE_ARGS[@]}" down --rmi local --remove-orphans
else
    docker compose "${COMPOSE_ARGS[@]}" down --remove-orphans
fi

echo -e "${GREEN}✅ Stopped${NC}"
