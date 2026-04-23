#!/bin/bash
# =============================================================
# CS4296 Project - Client Setup Script
# Usage: bash install_client.sh
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

require_var "SERVER_PUBLIC_IP"
require_var "SS_PORT"
require_var "SS_PASSWORD"
require_var "XRAY_UUID"
require_var "XRAY_PUBLIC_KEY"
require_var "XRAY_SHORT_ID"

echo "=============================="
echo " CS4296 Client Setup Starting"
echo "=============================="

# ── 1. System Update & Base Packages ──────────────────────────
echo "[1/6] Installing base packages..."
sudo apt update -y
sudo apt install -y shadowsocks-libev wireguard iperf3 curl sysstat net-tools

# ── 2. Install Xray ───────────────────────────────────────────
echo "[2/6] Installing Xray..."
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ── 3. Configure Shadowsocks Client ───────────────────────────
echo "[3/6] Configuring Shadowsocks client..."
sudo tee /etc/shadowsocks-libev/config.json > /dev/null << EOF
{
    "server": "${SERVER_PUBLIC_IP}",
    "server_port": ${SS_PORT},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${SS_PASSWORD}",
    "timeout": 86400,
    "method": "chacha20-ietf-poly1305"
}
EOF

# ── 4. Configure Xray Client ──────────────────────────────────
echo "[4/6] Configuring Xray client..."
sudo tee /usr/local/etc/xray/config.json > /dev/null << EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 1080,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {
      "auth": "noauth",
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${SERVER_PUBLIC_IP}",
        "port": 443,
        "users": [{
          "id": "${XRAY_UUID}",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "fingerprint": "chrome",
        "serverName": "www.microsoft.com",
        "publicKey": "${XRAY_PUBLIC_KEY}",
        "shortId": "${XRAY_SHORT_ID}",
        "spiderX": "/"
      }
    }
  }]
}
EOF
sudo systemctl enable xray
sudo systemctl restart xray

# ── 5. Configure WireGuard Client ─────────────────────────────
echo "[5/6] Generating WireGuard client keys..."
if [ ! -f /etc/wireguard/client_private.key ]; then
    wg genkey | sudo tee /etc/wireguard/client_private.key
    sudo chmod 600 /etc/wireguard/client_private.key
    sudo cat /etc/wireguard/client_private.key | wg pubkey | sudo tee /etc/wireguard/client_public.key
fi

CLIENT_PRIV=$(sudo cat /etc/wireguard/client_private.key)

# First run can happen before server setup. In that case, skip wg0 bring-up.
if [ -z "${WG_SERVER_PUBLIC_KEY:-}" ]; then
  echo ""
  echo "WG_SERVER_PUBLIC_KEY is empty. Skipping WireGuard peer setup on client for now."
  echo "After server setup, put WG_SERVER_PUBLIC_KEY in config.env and run this script again."
else
  echo "[6/6] Configuring and starting WireGuard client..."
  sudo tee /etc/wireguard/wg0.conf > /dev/null << EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = 10.8.0.2/32

[Peer]
PublicKey = ${WG_SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_PUBLIC_IP}:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
EOF
  sudo systemctl enable wg-quick@wg0
  sudo systemctl restart wg-quick@wg0
fi

echo ""
echo "=============================="
echo " Client Setup Complete!"
echo " Client WireGuard Public Key:"
sudo cat /etc/wireguard/client_public.key
echo "=============================="
echo " NOTE: Copy this key to config.env as WG_CLIENT_PUBLIC_KEY"
echo " Then run install_server.sh on server"