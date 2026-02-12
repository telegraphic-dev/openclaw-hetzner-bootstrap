#!/bin/bash
set -e

# Destroy an OpenClaw Hetzner server
# Usage: HETZNER_API_TOKEN=xxx ./destroy.sh --name server-name

echo "🗑️  OpenClaw Hetzner Destroyer"
echo "=============================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

[[ -z "$HETZNER_API_TOKEN" ]] && { echo -e "${RED}Set HETZNER_API_TOKEN${NC}"; exit 1; }

API="https://api.hetzner.cloud/v1"
AUTH="Authorization: Bearer $HETZNER_API_TOKEN"

# Parse --name
while [[ $# -gt 0 ]]; do
    case $1 in
        --name) SERVER_NAME="$2"; shift 2 ;;
        --list) 
            echo "Your servers:"
            curl -sf -H "$AUTH" "$API/servers" | jq -r '.servers[] | "  \(.name) (\(.server_type.name)) - \(.public_net.ipv4.ip)"'
            exit 0
            ;;
        *) echo "Usage: ./destroy.sh --name SERVER_NAME"; exit 1 ;;
    esac
done

[[ -z "$SERVER_NAME" ]] && { echo "Usage: ./destroy.sh --name SERVER_NAME"; echo "       ./destroy.sh --list"; exit 1; }

# Find server
SERVER_ID=$(curl -sf -H "$AUTH" "$API/servers" | jq -r ".servers[] | select(.name==\"$SERVER_NAME\") | .id")
[[ -z "$SERVER_ID" ]] && { echo -e "${RED}Server not found: $SERVER_NAME${NC}"; exit 1; }

SERVER_IP=$(curl -sf -H "$AUTH" "$API/servers/$SERVER_ID" | jq -r '.server.public_net.ipv4.ip')

echo -e "${YELLOW}Warning: This will permanently delete:${NC}"
echo "  Name: $SERVER_NAME"
echo "  IP:   $SERVER_IP"
echo ""
read -p "Type 'yes' to confirm: " CONFIRM

[[ "$CONFIRM" != "yes" ]] && { echo "Aborted."; exit 1; }

curl -sf -X DELETE -H "$AUTH" "$API/servers/$SERVER_ID" > /dev/null
echo -e "${GREEN}✅ Server $SERVER_NAME deleted${NC}"
