#!/bin/bash
set -e

# OpenClaw Hetzner Provisioner
# Creates a VPS and bootstraps OpenClaw automatically
#
# Usage: 
#   HETZNER_API_TOKEN=xxx ./provision.sh
#   HETZNER_API_TOKEN=xxx ./provision.sh --name my-agent --type cax11 --location fsn1

echo "🦞 OpenClaw Hetzner Provisioner"
echo "================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Defaults
SERVER_NAME="openclaw-$(date +%s)"
SERVER_TYPE="cax11"  # ARM, 2 vCPU, 4GB RAM, ~€4/mo
LOCATION="fsn1"      # Falkenstein, Germany
IMAGE="ubuntu-24.04"
SSH_KEY_NAME=""
SSH_KEY_FILE="$HOME/.ssh/id_ed25519.pub"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name) SERVER_NAME="$2"; shift 2 ;;
        --type) SERVER_TYPE="$2"; shift 2 ;;
        --location) LOCATION="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --ssh-key) SSH_KEY_NAME="$2"; shift 2 ;;
        --ssh-key-file) SSH_KEY_FILE="$2"; shift 2 ;;
        --help)
            echo "Usage: HETZNER_API_TOKEN=xxx ./provision.sh [options]"
            echo ""
            echo "Options:"
            echo "  --name NAME        Server name (default: openclaw-timestamp)"
            echo "  --type TYPE        Server type (default: cax11 ~€4/mo)"
            echo "                     Options: cax11, cax21, cax31, cpx11, cx22"
            echo "  --location LOC     Location (default: fsn1)"
            echo "                     Options: fsn1, nbg1, hel1, ash, hil"
            echo "  --image IMAGE      OS image (default: ubuntu-24.04)"
            echo "  --ssh-key NAME     Existing SSH key name in Hetzner"
            echo "  --ssh-key-file F   Local SSH public key file (default: ~/.ssh/id_ed25519.pub)"
            echo ""
            echo "Server types:"
            echo "  cax11  - ARM, 2 vCPU,  4GB RAM  - ~€4/mo (recommended)"
            echo "  cax21  - ARM, 4 vCPU,  8GB RAM  - ~€8/mo"
            echo "  cax31  - ARM, 8 vCPU, 16GB RAM  - ~€15/mo"
            echo "  cpx11  - x86, 2 vCPU,  2GB RAM  - ~€5/mo"
            echo "  cx22   - x86, 2 vCPU,  4GB RAM  - ~€6/mo"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Check API token
[[ -z "$HETZNER_API_TOKEN" ]] && error "Set HETZNER_API_TOKEN environment variable"

API="https://api.hetzner.cloud/v1"
AUTH="Authorization: Bearer $HETZNER_API_TOKEN"

# Test API connection
info "Testing Hetzner API connection..."
ACCOUNT=$(curl -sf -H "$AUTH" "$API/servers" | jq -r '.servers | length') || error "API connection failed. Check your token."
info "API connected. You have $ACCOUNT existing servers."

# ============================================
# 1. Handle SSH Key
# ============================================
if [[ -z "$SSH_KEY_NAME" ]]; then
    # Upload SSH key if not specified
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        error "SSH key not found: $SSH_KEY_FILE\nGenerate one: ssh-keygen -t ed25519"
    fi
    
    SSH_KEY_CONTENT=$(cat "$SSH_KEY_FILE")
    SSH_KEY_NAME="openclaw-$(whoami)-$(date +%Y%m%d)"
    
    info "Uploading SSH key: $SSH_KEY_NAME"
    
    UPLOAD_RESULT=$(curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
        "$API/ssh_keys" \
        -d "{\"name\": \"$SSH_KEY_NAME\", \"public_key\": \"$SSH_KEY_CONTENT\"}" 2>&1) || true
    
    if echo "$UPLOAD_RESULT" | jq -e '.ssh_key.id' > /dev/null 2>&1; then
        SSH_KEY_ID=$(echo "$UPLOAD_RESULT" | jq -r '.ssh_key.id')
        info "SSH key uploaded (ID: $SSH_KEY_ID)"
    elif echo "$UPLOAD_RESULT" | grep -q "uniqueness_error"; then
        # Key already exists, find it
        SSH_KEY_ID=$(curl -sf -H "$AUTH" "$API/ssh_keys" | jq -r ".ssh_keys[] | select(.public_key | startswith(\"$(echo $SSH_KEY_CONTENT | cut -d' ' -f1-2)\")) | .id")
        info "SSH key already exists (ID: $SSH_KEY_ID)"
    else
        error "Failed to upload SSH key: $UPLOAD_RESULT"
    fi
else
    # Find existing key by name
    SSH_KEY_ID=$(curl -sf -H "$AUTH" "$API/ssh_keys" | jq -r ".ssh_keys[] | select(.name==\"$SSH_KEY_NAME\") | .id")
    [[ -z "$SSH_KEY_ID" ]] && error "SSH key not found: $SSH_KEY_NAME"
    info "Using existing SSH key: $SSH_KEY_NAME (ID: $SSH_KEY_ID)"
fi

# ============================================
# 2. Create Server
# ============================================
info "Creating server: $SERVER_NAME ($SERVER_TYPE in $LOCATION)..."

# Cloud-init to run bootstrap
CLOUD_INIT=$(cat << 'CLOUDINIT'
#cloud-config
runcmd:
  - curl -fsSL https://raw.githubusercontent.com/telegraphic-dev/openclaw-hetzner-bootstrap/main/bootstrap.sh | bash > /var/log/openclaw-bootstrap.log 2>&1
  - echo "BOOTSTRAP_COMPLETE" >> /var/log/openclaw-bootstrap.log
CLOUDINIT
)

CREATE_RESULT=$(curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
    "$API/servers" \
    -d "{
        \"name\": \"$SERVER_NAME\",
        \"server_type\": \"$SERVER_TYPE\",
        \"location\": \"$LOCATION\",
        \"image\": \"$IMAGE\",
        \"ssh_keys\": [$SSH_KEY_ID],
        \"user_data\": $(echo "$CLOUD_INIT" | jq -Rs .)
    }") || error "Failed to create server"

SERVER_ID=$(echo "$CREATE_RESULT" | jq -r '.server.id')
SERVER_IP=$(echo "$CREATE_RESULT" | jq -r '.server.public_net.ipv4.ip')
ROOT_PASSWORD=$(echo "$CREATE_RESULT" | jq -r '.root_password // empty')

info "Server created! ID: $SERVER_ID"
info "IP: $SERVER_IP"

# ============================================
# 3. Wait for server to be ready
# ============================================
info "Waiting for server to boot..."
while true; do
    STATUS=$(curl -sf -H "$AUTH" "$API/servers/$SERVER_ID" | jq -r '.server.status')
    if [[ "$STATUS" == "running" ]]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""
info "Server is running!"

# ============================================
# 4. Wait for SSH to be available
# ============================================
info "Waiting for SSH to be available..."
for i in {1..60}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes root@$SERVER_IP "echo ok" &>/dev/null; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""
info "SSH is available!"

# ============================================
# 5. Wait for bootstrap to complete
# ============================================
info "Waiting for OpenClaw bootstrap to complete (this takes 2-3 minutes)..."
for i in {1..60}; do
    if ssh -o StrictHostKeyChecking=no root@$SERVER_IP "grep -q BOOTSTRAP_COMPLETE /var/log/openclaw-bootstrap.log 2>/dev/null" &>/dev/null; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Get the gateway token
GATEWAY_TOKEN=$(ssh -o StrictHostKeyChecking=no root@$SERVER_IP "grep -oP '\"token\": \"\K[^\"]+' /home/openclaw/.openclaw/openclaw.json 2>/dev/null" || echo "CHECK_SERVER")

# ============================================
# Summary
# ============================================
echo ""
echo "======================================"
echo -e "${GREEN}✅ OpenClaw Server Ready!${NC}"
echo "======================================"
echo ""
echo -e "${CYAN}Server Details:${NC}"
echo "  Name:     $SERVER_NAME"
echo "  IP:       $SERVER_IP"
echo "  Type:     $SERVER_TYPE"
echo "  Location: $LOCATION"
echo ""
echo -e "${CYAN}Gateway Token:${NC}"
echo -e "  ${YELLOW}$GATEWAY_TOKEN${NC}"
echo ""
echo -e "${CYAN}Connect:${NC}"
echo "  SSH (root):     ssh root@$SERVER_IP"
echo "  SSH (openclaw): ssh openclaw@$SERVER_IP"
echo ""
echo -e "${CYAN}Access OpenClaw UI:${NC}"
echo "  1. Create SSH tunnel:"
echo "     ssh -L 18789:127.0.0.1:18789 openclaw@$SERVER_IP"
echo "  2. Open: http://127.0.0.1:18789"
echo "  3. Paste your gateway token"
echo ""
echo -e "${CYAN}Start Gateway:${NC}"
echo "  ssh openclaw@$SERVER_IP 'sudo systemctl start openclaw-gateway'"
echo ""
echo -e "${CYAN}View Logs:${NC}"
echo "  ssh openclaw@$SERVER_IP 'journalctl -u openclaw-gateway -f'"
echo ""
echo -e "${CYAN}Configure Channels:${NC}"
echo "  ssh openclaw@$SERVER_IP"
echo "  openclaw onboard"
echo ""

# Save details to file
DETAILS_FILE="openclaw-${SERVER_NAME}.txt"
cat > "$DETAILS_FILE" << EOF
OpenClaw Server: $SERVER_NAME
Created: $(date)

IP: $SERVER_IP
Gateway Token: $GATEWAY_TOKEN

SSH: ssh openclaw@$SERVER_IP
Tunnel: ssh -L 18789:127.0.0.1:18789 openclaw@$SERVER_IP
UI: http://127.0.0.1:18789
EOF

info "Details saved to: $DETAILS_FILE"
