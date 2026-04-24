#!/bin/bash
# =============================================================
# CS4296 Project - WireGuard Benchmark Script (Client Side)
# Usage: bash run_wireguard_benchmark.sh
# =============================================================
set -euo pipefail

CONFIG_FILE="$(dirname "$0")/../config.env"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: config.env not found at ${CONFIG_FILE}"
  exit 1
fi

source <(sed 's/\r$//' "${CONFIG_FILE}")

RESULT_DIR="$(dirname "$0")/../results/wireguard"
mkdir -p "$RESULT_DIR"

TEST_FILE_NAME="${WG_TEST_FILE_NAME:-testfile_3gb.bin}"

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
echo " Starting WireGuard..."
echo "=============================="
sudo wg-quick up wg0
sleep 3

echo ">>> Running Speed Test..."
# CPU monitor in background
pidstat -u 1 60 > "$RESULT_DIR/cpu.txt" 2>&1 &
CPU_PID=$!

# Memory monitor in background (use free -m for kernel module)
(
  for i in $(seq 1 30); do
    free -m | awk -v ts="$(date +%H:%M:%S)" '/Mem:/ {printf "[%s] Used: %d MB\n", ts, $3}'
    sleep 2
  done
) > "$RESULT_DIR/memory.txt" 2>&1 &
MEM_PID=$!

# Speed test via WireGuard tunnel (no proxy needed)
curl -o /dev/null \
  -w "\nSpeed: %{speed_download} bytes/sec\nTime: %{time_total}s\n" \
  "http://10.8.0.1:8080/${TEST_FILE_NAME}" 2>&1 | tee "$RESULT_DIR/speed.txt"

# Cleanup
kill $CPU_PID $MEM_PID 2>/dev/null || true
sudo wg-quick down wg0 2>/dev/null || true

echo ""
echo "=============================="
echo " WireGuard Benchmark Done!"
echo " Results saved to: $RESULT_DIR"
echo "=============================="
