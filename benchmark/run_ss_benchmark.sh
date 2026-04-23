#!/bin/bash
# =============================================================
# CS4296 Project - Shadowsocks Benchmark Script (Client Side)
# Usage: bash run_ss_benchmark.sh
# =============================================================
set -euo pipefail

CONFIG_FILE="$(dirname "$0")/../config.env"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: config.env not found at ${CONFIG_FILE}"
  exit 1
fi

source <(sed 's/\r$//' "${CONFIG_FILE}")

if [ -z "${SERVER_PUBLIC_IP:-}" ]; then
  echo "ERROR: Missing SERVER_PUBLIC_IP in config.env"
  exit 1
fi

RESULT_DIR="$(dirname "$0")/../results/ss"
mkdir -p "$RESULT_DIR"

TEST_FILE_NAME="${SS_TEST_FILE_NAME:-testfile_3gb.bin}"

echo "=============================="
echo " Stopping all VPN services..."
echo "=============================="
sudo wg-quick down wg0 2>/dev/null || true
sudo pkill xray 2>/dev/null || true
sudo pkill ss-local 2>/dev/null || true
sudo systemctl stop xray 2>/dev/null || true
sudo systemctl stop shadowsocks-libev 2>/dev/null || true
sleep 2

echo "=============================="
echo " Starting Shadowsocks Client..."
echo "=============================="
sudo ss-local -c /etc/shadowsocks-libev/config.json &
sleep 3
SS_PID=$(pgrep -n ss-local || true)
if [ -z "$SS_PID" ]; then
  echo "ERROR: ss-local did not start correctly"
  exit 1
fi

echo ">>> Running Speed Test..."
# CPU monitor in background
pidstat -u -p $SS_PID 1 60 > "$RESULT_DIR/cpu.txt" 2>&1 &
CPU_PID=$!

# Memory monitor in background
(
  while kill -0 $SS_PID 2>/dev/null; do
    ps -p $SS_PID -o rss= 2>/dev/null | awk -v ts="$(date +%H:%M:%S)" '{printf "[%s] RSS: %.2f MB\n", ts, $1/1024}'
    sleep 2
  done
) > "$RESULT_DIR/memory.txt" 2>&1 &
MEM_PID=$!

# Speed test (foreground)
curl -x socks5h://127.0.0.1:1080 \
  -o /dev/null \
  -w "\nSpeed: %{speed_download} bytes/sec\nTime: %{time_total}s\n" \
  "http://${SERVER_PUBLIC_IP}:8080/${TEST_FILE_NAME}" 2>&1 | tee "$RESULT_DIR/speed.txt"

# Cleanup
kill $CPU_PID $MEM_PID 2>/dev/null || true
sudo pkill ss-local 2>/dev/null || true

echo ""
echo "=============================="
echo " Shadowsocks Benchmark Done!"
echo " Results saved to: $RESULT_DIR"
echo "=============================="
