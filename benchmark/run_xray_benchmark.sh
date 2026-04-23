#!/bin/bash
# =============================================================
# CS4296 Project - Xray Benchmark Script (Client Side)
# Usage: bash run_xray_benchmark.sh
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

RESULT_DIR="$(dirname "$0")/../results/xray"
mkdir -p "$RESULT_DIR"

TEST_FILE_NAME="${XRAY_TEST_FILE_NAME:-testfile_3gb.bin}"
TARGET_HOST="${XRAY_TARGET_HOST:-$SERVER_PUBLIC_IP}"

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
echo " Starting Xray Client..."
echo "=============================="
/usr/local/bin/xray run -c /usr/local/etc/xray/config.json &
sleep 3
XRAY_PID=$(pgrep -n xray || true)
if [ -z "$XRAY_PID" ]; then
  echo "ERROR: xray did not start correctly"
  exit 1
fi

echo ">>> Running Speed Test..."
# CPU monitor in background
pidstat -u -p $XRAY_PID 1 60 > "$RESULT_DIR/cpu.txt" 2>&1 &
CPU_PID=$!

# Memory monitor in background
(
  while kill -0 $XRAY_PID 2>/dev/null; do
    ps -p $XRAY_PID -o rss= 2>/dev/null | awk -v ts="$(date +%H:%M:%S)" '{printf "[%s] RSS: %.2f MB\n", ts, $1/1024}'
    sleep 2
  done
) > "$RESULT_DIR/memory.txt" 2>&1 &
MEM_PID=$!

# Speed test (foreground)
curl -x socks5h://127.0.0.1:1080 \
  -o /dev/null \
  -w "\nSpeed: %{speed_download} bytes/sec\nTime: %{time_total}s\n" \
  "http://${TARGET_HOST}:8080/${TEST_FILE_NAME}" 2>&1 | tee "$RESULT_DIR/speed.txt"

# Cleanup
kill $CPU_PID $MEM_PID 2>/dev/null || true
sudo pkill xray 2>/dev/null || true

echo ""
echo "=============================="
echo " Xray Benchmark Done!"
echo " Results saved to: $RESULT_DIR"
echo "=============================="
