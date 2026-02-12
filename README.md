# OpenClaw Hetzner Bootstrap

One-command setup for OpenClaw on Hetzner (or any Ubuntu/Debian VPS).

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/telegraphic-dev/openclaw-hetzner-bootstrap/main/bootstrap.sh | sudo bash
```

## What it does

1. **System updates** - apt upgrade
2. **Docker** - installs Docker CE
3. **Node.js 22** - required for OpenClaw
4. **OpenClaw** - latest from npm
5. **Non-root user** - creates `openclaw` user with sudo
6. **Firewall (UFW)** - allows only SSH, HTTP, HTTPS
7. **fail2ban** - blocks brute-force SSH attacks
8. **SSH hardening** - disables root login & password auth
9. **Auto-updates** - enables unattended-upgrades
10. **Workspace** - creates ~/workspace
11. **Gateway config** - generates strong token, binds to localhost
12. **Systemd service** - auto-start on boot

## After Installation

1. **Save the gateway token** shown at the end
2. **Add your SSH key**:
   ```bash
   echo "your-public-key" >> /home/openclaw/.ssh/authorized_keys
   ```
3. **SSH as openclaw user**:
   ```bash
   ssh openclaw@YOUR_SERVER_IP
   ```
4. **Configure channels** (Telegram, etc.):
   ```bash
   openclaw onboard
   ```
5. **Start the gateway**:
   ```bash
   sudo systemctl start openclaw-gateway
   ```
6. **Access the UI** via SSH tunnel:
   ```bash
   ssh -L 18789:127.0.0.1:18789 openclaw@YOUR_SERVER_IP
   # Then open http://127.0.0.1:18789
   ```

## Optional: Tailscale

For easy VPN access without SSH tunnels:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Then access via Tailscale IP: `http://100.x.x.x:18789`

## Optional: Coolify

For self-hosted app deployments alongside OpenClaw:

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

## Security Notes

- Gateway binds to `127.0.0.1` (not public)
- Access only via SSH tunnel or Tailscale
- Root SSH disabled after setup
- Password authentication disabled
- fail2ban protects against brute-force
- UFW allows only ports 22, 80, 443

## Requirements

- Ubuntu 22.04+ or Debian 12+
- Root access
- 1GB+ RAM (2GB recommended)
- Hetzner CAX11 (~€4/mo) works great

## License

MIT

---

## Full Automation with Hetzner API

Provision a VPS and bootstrap OpenClaw in one command:

```bash
HETZNER_API_TOKEN=xxx ./provision.sh
```

### Options

```
--name NAME        Server name (default: openclaw-timestamp)
--type TYPE        Server type (default: cax11 ~€4/mo)
--location LOC     Location (default: fsn1 - Germany)
--ssh-key NAME     Use existing Hetzner SSH key
--ssh-key-file F   Local SSH public key (default: ~/.ssh/id_ed25519.pub)
```

### Server Types

| Type  | CPU | RAM  | Price  |
|-------|-----|------|--------|
| cax11 | 2 ARM | 4GB | ~€4/mo |
| cax21 | 4 ARM | 8GB | ~€8/mo |
| cax31 | 8 ARM | 16GB | ~€15/mo |
| cpx11 | 2 x86 | 2GB | ~€5/mo |
| cx22  | 2 x86 | 4GB | ~€6/mo |

### Example

```bash
# Create a beefy server named "my-agent" in Helsinki
HETZNER_API_TOKEN=xxx ./provision.sh --name my-agent --type cax31 --location hel1
```

### Get Hetzner API Token

1. Go to https://console.hetzner.cloud
2. Select your project (or create one)
3. Security → API Tokens → Generate API Token
4. Give it Read & Write permissions
