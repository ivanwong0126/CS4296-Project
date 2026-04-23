CS4296 Project setup guide for testing 3 protocols on AWS EC2:

- Shadowsocks
- Xray (VLESS + Vision + Reality)
- WireGuard

## Files

- `config.env`: all shared variables
- `setup/install_client.sh`: client installation and config
- `setup/install_server.sh`: server installation and config
- `benchmark/`: client benchmark scripts for Shadowsocks, Xray, and WireGuard
- `result/`: manual/summary benchmark result text files

## Requirements

- Ubuntu/Debian EC2 on both client and server
- User with `sudo` privilege
- Internet access for apt and Xray installer

## 1) Fill `config.env`

Required values:

- `SERVER_PUBLIC_IP`
- `SS_PORT`, `SS_PASSWORD`
- `XRAY_UUID`, `XRAY_PUBLIC_KEY`, `XRAY_PRIVATE_KEY`, `XRAY_SHORT_ID`
- `WG_CLIENT_PUBLIC_KEY` (filled after first client run)
- `WG_SERVER_PUBLIC_KEY` (filled after server run)

## 2) Run in this order

### Step A: Run on Client first (generate client WG key)

```bash
bash setup/install_client.sh
```

Copy output `Client WireGuard Public Key` into `config.env` as `WG_CLIENT_PUBLIC_KEY`.

### Step B: Run on Server

```bash
bash setup/install_server.sh
```

Copy output `Server WireGuard Public Key` into `config.env` on client as `WG_SERVER_PUBLIC_KEY`.

### Step C: Run on Client again (activate WireGuard peer)

```bash
bash setup/install_client.sh
```

After this, Shadowsocks, Xray, and WireGuard are all configured and started.

## 3) Run benchmark scripts (Client)

```bash
bash benchmark/run_ss_benchmark.sh
bash benchmark/run_xray_benchmark.sh
bash benchmark/run_wireguard_benchmark.sh
```

Benchmark scripts save raw outputs to `results/ss`, `results/xray`, and `results/wireguard`.
You can keep final summarized results in `result/`.

## Notes

- `install_client.sh` allows first run without `WG_SERVER_PUBLIC_KEY` and prints the key you need.
- `install_server.sh` requires `WG_CLIENT_PUBLIC_KEY` to be present.
- Both scripts read `config.env` safely even if file has Windows line endings (CRLF).