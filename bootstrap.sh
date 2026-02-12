#!/bin/bash
set -e

# OpenClaw Hetzner Bootstrap Script
# Usage: curl -fsSL https://raw.githubusercontent.com/telegraphic-dev/openclaw-hetzner-bootstrap/main/bootstrap.sh | bash

echo "🦞 OpenClaw Hetzner Bootstrap"
echo "=============================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
[[ $EUID -ne 0 ]] && error "Run as root: sudo bash bootstrap.sh"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    error "Cannot detect OS"
fi

info "Detected OS: $OS"

# ============================================
# 1. System Updates
# ============================================
info "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ============================================
# 2. Install Dependencies
# ============================================
info "Installing dependencies..."
apt-get install -y -qq \
    curl wget git ca-certificates gnupg lsb-release \
    ufw fail2ban unattended-upgrades \
    jq htop

# ============================================
# 3. Install Docker
# ============================================
if ! command -v docker &> /dev/null; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
else
    info "Docker already installed"
fi

# ============================================
# 4. Install Node.js 22
# ============================================
if ! command -v node &> /dev/null || [[ $(node -v | cut -d. -f1 | tr -d 'v') -lt 22 ]]; then
    info "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y -qq nodejs
else
    info "Node.js $(node -v) already installed"
fi

# ============================================
# 5. Install OpenClaw
# ============================================
info "Installing OpenClaw..."
npm install -g openclaw@latest

# ============================================
# 6. Create non-root user
# ============================================
USERNAME="openclaw"
if ! id "$USERNAME" &>/dev/null; then
    info "Creating user: $USERNAME"
    useradd -m -s /bin/bash $USERNAME
    usermod -aG docker $USERNAME
    
    # Passwordless sudo
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
    chmod 440 /etc/sudoers.d/$USERNAME
    
    # Copy SSH keys from root
    if [ -f /root/.ssh/authorized_keys ]; then
        mkdir -p /home/$USERNAME/.ssh
        cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/
        chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
        chmod 700 /home/$USERNAME/.ssh
        chmod 600 /home/$USERNAME/.ssh/authorized_keys
    fi
else
    info "User $USERNAME already exists"
fi

# ============================================
# 7. Configure Firewall (UFW)
# ============================================
info "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
# Allow Docker internal traffic
ufw allow from 10.0.0.0/8 to any comment 'Docker internal'
ufw allow from 172.16.0.0/12 to any comment 'Docker internal'
echo "y" | ufw enable

# ============================================
# 8. Configure fail2ban
# ============================================
info "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# ============================================
# 9. Harden SSH
# ============================================
info "Hardening SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup
cp $SSH_CONFIG ${SSH_CONFIG}.backup.$(date +%Y%m%d)

# Apply hardening
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSH_CONFIG

# Restart SSH
systemctl restart sshd

# ============================================
# 10. Enable automatic security updates
# ============================================
info "Enabling automatic security updates..."
dpkg-reconfigure -plow unattended-upgrades

# ============================================
# 11. Create workspace
# ============================================
WORKSPACE="/home/$USERNAME/workspace"
info "Creating workspace at $WORKSPACE..."
mkdir -p $WORKSPACE
chown -R $USERNAME:$USERNAME $WORKSPACE

# ============================================
# 12. Initialize OpenClaw
# ============================================
info "Setting up OpenClaw directory..."
OPENCLAW_DIR="/home/$USERNAME/.openclaw"
mkdir -p $OPENCLAW_DIR
chown -R $USERNAME:$USERNAME $OPENCLAW_DIR

# Generate strong gateway token
GATEWAY_TOKEN=$(openssl rand -hex 32)

# Create basic config
cat > $OPENCLAW_DIR/openclaw.json << EOF
{
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "bind": "127.0.0.1"
  },
  "workspace": "$WORKSPACE"
}
EOF
chmod 600 $OPENCLAW_DIR/openclaw.json
chown $USERNAME:$USERNAME $OPENCLAW_DIR/openclaw.json

# ============================================
# 13. Create systemd service
# ============================================
info "Creating systemd service..."
cat > /etc/systemd/system/openclaw-gateway.service << EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=$USERNAME
WorkingDirectory=/home/$USERNAME
ExecStart=/usr/bin/openclaw gateway
Restart=always
RestartSec=10
Environment=HOME=/home/$USERNAME
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw-gateway

# ============================================
# Summary
# ============================================
echo ""
echo "=============================="
echo -e "${GREEN}✅ OpenClaw Bootstrap Complete!${NC}"
echo "=============================="
echo ""
echo "Gateway token (save this!):"
echo -e "${YELLOW}$GATEWAY_TOKEN${NC}"
echo ""
echo "Next steps:"
echo "1. Add your SSH key to /home/$USERNAME/.ssh/authorized_keys"
echo "2. SSH as: ssh $USERNAME@$(curl -s ifconfig.me)"
echo "3. Configure channels: openclaw onboard"
echo "4. Start gateway: sudo systemctl start openclaw-gateway"
echo "5. Access UI: ssh -L 18789:127.0.0.1:18789 $USERNAME@SERVER_IP"
echo "   Then open: http://127.0.0.1:18789"
echo ""
echo "Optional: Install Tailscale for easy VPN access:"
echo "  curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
echo ""
