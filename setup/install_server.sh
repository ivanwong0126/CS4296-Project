#!/bin/bash
# =============================================================
# CS4296 Project - Server Setup Script
# Usage: bash install_server.sh
# =============================================================

set -euo pipefail

CONFIG_FILE="$(dirname "$0")/../config.env"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: config.env not found at ${CONFIG_FILE}"
  exit 1
fi

source <(sed 's/\r$//' "${CONFIG_FILE}")

require_var() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    echo "ERROR: Missing ${var_name} in config.env"
    exit 1
  fi
}

require_var "SS_PORT"
require_var "SS_PASSWORD"
require_var "XRAY_UUID"
require_var "XRAY_PRIVATE_KEY"
require_var "XRAY_SHORT_ID"
require_var "WG_CLIENT_PUBLIC_KEY"

echo "=============================="
echo " CS4296 Server Setup Starting"
echo "=============================="

# ── 1. System Update & Base Packages ──────────────────────────
echo "[1/8] Installing base packages..."
sudo apt update -y
sudo apt install -y shadowsocks-libev wireguard iperf3 curl sysstat net-tools python3

# ── 2. Install Xray ───────────────────────────────────────────
echo "[2/8] Installing Xray..."
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ── 3. Enable IP Forwarding ───────────────────────────────────
echo "[3/8] Enabling IP forwarding..."
if ! grep -q "^net.ipv4.ip_forward = 1$" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# ── 4. Configure Shadowsocks Server ───────────────────────────
echo "[4/8] Configuring Shadowsocks..."
sudo tee /etc/shadowsocks-libev/config.json > /dev/null << EOF
{
    "server": "0.0.0.0",
    "mode": "tcp_and_udp",
    "server_port": ${SS_PORT},
    "local_port": 1080,
    "password": "${SS_PASSWORD}",
    "timeout": 86400,
    "method": "chacha20-ietf-poly1305"
}
EOF
sudo systemctl enable shadowsocks-libev
sudo systemctl restart shadowsocks-libev

# ── 5. Configure Xray Server ──────────────────────────────────
echo "[5/8] Configuring Xray..."
sudo tee /usr/local/etc/xray/config.json > /dev/null << EOF
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "${XRAY_UUID}",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "${XRAY_PRIVATE_KEY}",
        "shortIds": ["${XRAY_SHORT_ID}"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
sudo systemctl enable xray
sudo systemctl restart xray

# ── 6. Configure WireGuard Server ─────────────────────────────
echo "[6/8] Configuring WireGuard..."
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5; exit}')
if [ -z "${DEFAULT_IFACE}" ]; then
  DEFAULT_IFACE="eth0"
fi

# Generate server keypair if not exists
if [ ! -f /etc/wireguard/server_private.key ]; then
    wg genkey | sudo tee /etc/wireguard/server_private.key
    sudo chmod 600 /etc/wireguard/server_private.key
    sudo cat /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
fi

SERVER_PRIV=$(sudo cat /etc/wireguard/server_private.key)

sudo tee /etc/wireguard/wg0.conf > /dev/null << EOF
[Interface]
PrivateKey = ${SERVER_PRIV}
Address = 10.8.0.1/24
ListenPort = 51820
PostUp = iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE

[Peer]
PublicKey = ${WG_CLIENT_PUBLIC_KEY}
AllowedIPs = 10.8.0.2/32
EOF
sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0

# ── 7. Prepare Benchmark Test Files ───────────────────────────
echo "[7/8] Preparing benchmark test files..."
sudo mkdir -p /var/www/html

if [ ! -f /var/www/html/testfile_2gb.bin ]; then
  sudo fallocate -l 2G /var/www/html/testfile_2gb.bin
fi

if [ ! -f /var/www/html/testfile_3gb.bin ]; then
  sudo fallocate -l 3G /var/www/html/testfile_3gb.bin
fi

if [ ! -f /var/www/html/testfile.bin ]; then
  sudo ln -s /var/www/html/testfile_3gb.bin /var/www/html/testfile.bin
fi

# ── 8. Start Benchmark HTTP Server ────────────────────────────
echo "[8/8] Starting benchmark HTTP server on port 8080..."
sudo tee /etc/systemd/system/benchmark-http.service > /dev/null << 'EOF'
[Unit]
Description=CS4296 Benchmark HTTP Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/www/html
ExecStart=/usr/bin/python3 -m http.server 8080 --directory /var/www/html
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable benchmark-http.service
sudo systemctl restart benchmark-http.service

echo ""
echo "=============================="
echo " Server Setup Complete!"
echo " Server WireGuard Public Key:"
sudo cat /etc/wireguard/server_public.key
echo "=============================="
echo " Next: Put this key into config.env as WG_SERVER_PUBLIC_KEY on client"
echo " Then re-run install_client.sh on the Client EC2"
echo " Benchmark files ready at /var/www/html/"
echo " HTTP benchmark server: http://0.0.0.0:8080"