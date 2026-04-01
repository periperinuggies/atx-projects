#!/bin/bash
# ============================================================
# Larsen Ventures — Warehouse Pi Setup Script
# Run as: bash setup.sh
# Target: Raspberry Pi 4B, Pi OS Lite 64-bit, hostname: warehouse-pi
# ============================================================

set -e
BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}[•]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

log "Starting Larsen Ventures warehouse Pi setup..."

# ── 1. System update ─────────────────────────────────────────
log "Updating system packages..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq
ok "System updated"

# ── 2. Essentials ────────────────────────────────────────────
log "Installing essentials..."
sudo apt-get install -y -qq curl wget git unzip ffmpeg
ok "Essentials installed"

# ── 3. Tailscale ─────────────────────────────────────────────
log "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
ok "Tailscale installed — approve in Tailscale admin console"
echo ""
echo "  Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'pending approval')"
echo ""

# ── 4. go2rtc ────────────────────────────────────────────────
log "Installing go2rtc..."
GO2RTC_VER="1.9.14"
mkdir -p ~/go2rtc
cd ~/go2rtc
wget -q "https://github.com/AlexxIT/go2rtc/releases/download/v${GO2RTC_VER}/go2rtc_linux_arm64" -O go2rtc
chmod +x go2rtc
ok "go2rtc ${GO2RTC_VER} installed"

# ── 5. go2rtc config ─────────────────────────────────────────
log "Writing go2rtc config (NVR placeholder — update IP before starting)..."
cat > ~/go2rtc/go2rtc.yaml << 'EOF'
api:
  listen: ":1984"
  origin: "*"

rtsp:
  listen: ":8554"

log:
  level: warn

streams:
  # UPDATE: replace 192.168.x.x with actual NVR IP on warehouse network
  # Dahua NVR — main streams (1080p)
  ch1: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=1&subtype=0
  ch2: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=2&subtype=0
  ch3: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=3&subtype=0
  ch4: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=4&subtype=0
  ch5: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=5&subtype=0
  ch6: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=6&subtype=0
  ch7: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=7&subtype=0
  ch8: rtsp://admin:PASSWORD@192.168.x.x:554/cam/realmonitor?channel=8&subtype=0
EOF
ok "go2rtc config written — update NVR IP and password before starting"

# ── 6. go2rtc systemd service ────────────────────────────────
log "Creating go2rtc systemd service..."
sudo tee /etc/systemd/system/go2rtc.service > /dev/null << EOF
[Unit]
Description=go2rtc stream server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=chappie
WorkingDirectory=/home/chappie/go2rtc
ExecStart=/home/chappie/go2rtc/go2rtc -config /home/chappie/go2rtc/go2rtc.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable go2rtc
ok "go2rtc service created (not started — update config first)"

# ── 7. Cloudflare tunnel ──────────────────────────────────────
log "Installing cloudflared..."
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update -qq && sudo apt-get install -y -qq cloudflared
ok "cloudflared installed"

log "Writing Cloudflare tunnel config placeholder..."
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << 'EOF'
# UPDATE: replace with actual tunnel ID and credentials file
# Run: cloudflared tunnel login
# Then: cloudflared tunnel create warehouse-pi
# Then update tunnel ID and credentials-file below

tunnel: TUNNEL-ID-HERE
credentials-file: /home/chappie/.cloudflared/TUNNEL-ID-HERE.json

ingress:
  - hostname: cameras.larsenfamily.com.au
    service: http://localhost:1984
  - service: http_status:404
EOF
ok "Cloudflare tunnel config written — complete login + tunnel create before starting"

# ── 8. Summary ───────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  Setup complete. Remaining manual steps:"
echo ""
echo "  1. Approve Pi in Tailscale admin console"
echo "     https://login.tailscale.com/admin/machines"
echo ""
echo "  2. Update NVR IP + password in ~/go2rtc/go2rtc.yaml"
echo "     Then: sudo systemctl start go2rtc"
echo "     Test: curl http://localhost:1984/api/streams"
echo ""
echo "  3. Cloudflare tunnel auth:"
echo "     cloudflared tunnel login"
echo "     cloudflared tunnel create warehouse-pi"
echo "     (update ~/.cloudflared/config.yml with new tunnel ID)"
echo "     sudo cloudflared service install"
echo "     sudo systemctl start cloudflared"
echo ""
echo "  4. Update Cloudflare tunnel config on VM to remove"
echo "     cameras.larsenfamily.com.au (Pi takes over that route)"
echo ""
echo "  5. Tell Chappie the Pi Tailscale IP + NVR IP and"
echo "     I'll do the rest remotely."
echo "════════════════════════════════════════════════════════"
