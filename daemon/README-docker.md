# Clawdmeter — full Docker deployment (Linux)

A self-contained Docker Compose stack that runs the BLE daemon **and** keeps its
Claude OAuth token fresh, so it works unattended 24/7 on a headless Linux host.
Claude Code does **not** need to be installed on the host.

## Two services

| Service | Job |
|---|---|
| `token-refresher` | Refreshes the OAuth access token (using the stored refresh token) before it expires, into a shared volume. The base daemon never refreshes, and the token expires in ~8h. |
| `daemon` | Scans for the device over BLE and pushes usage to it. Reads the token from the shared volume every poll. |

## ⚠️ Linux host only

BLE in a container needs the **host's** networking and BlueZ stack (via the
system D-Bus socket). This works on a native Linux host only — **Docker Desktop
(Windows/macOS) cannot access the Bluetooth radio**. The host must also be
within **~10 m** of the device with a working Bluetooth adapter.

## Prerequisites (Ubuntu host)

- Docker Engine + Compose plugin.
- `sudo systemctl enable --now bluetooth` (host BlueZ).
- Your Claude credentials copied in **once** (no Claude Code needed on the host):

```bash
cd daemon
mkdir -p secrets
# from a machine where you've run `claude login`:
cp ~/.claude/.credentials.json secrets/.credentials.json
```

That file is git-ignored. The refresher seeds an internal volume from it on
first run, then self-maintains the token — you don't need to touch it again
unless the refresh token itself is ever revoked.

## Transports

Two ways to reach the device — pick one with `-t`:

| Transport | Flag | Needs | When |
|---|---|---|---|
| Bluetooth LE | `-t ble` (default) | a host BT adapter + BlueZ | normal wireless operation |
| USB serial | `-t usb` | the device's USB cable plugged into the host | no BT adapter, or a wired setup |

The USB path sends the same usage JSON down the device's serial line (`/dev/ttyUSB0`);
the firmware renders it identically. No Bluetooth, D-Bus, or host networking involved.
Note: opening the serial port resets the device once on daemon start (then it stays up).

## Usage

```bash
cd daemon
./start.sh -d                 # BLE (default), detached
./start.sh -t usb -d          # USB serial, detached
docker compose logs -f        # watch the services
./stop.sh                     # stop (keeps the refreshed-token volume)
./stop.sh --rmi               # stop + remove the image
./stop.sh -v                  # stop + wipe volumes (re-seeds from secrets next start)
```

Healthy logs look like:
```
clawdmeter-token-refresher | refresher: refreshed OK — next expiry in 480 min
clawdmeter-daemon          | Scanning for 'Clawdmeter' (8.0s)...
clawdmeter-daemon          | Found: XX:XX:XX:XX:XX:XX
clawdmeter-daemon          | Connected
clawdmeter-daemon          | Sending: {"s":...,"w":...}
```

## How the token stays fresh

The refresher checks the token every `REFRESH_CHECK_INTERVAL` (default 10 min)
and refreshes when under `REFRESH_MARGIN` (default 30 min) to expiry, calling
Claude Code's public OAuth token endpoint with the stored refresh token — the
same grant Claude Code performs for your own account. It refreshes once at
startup too (`REFRESH_ON_START=true`) so you can confirm it works immediately in
the logs. All endpoints/IDs are overridable in `.env` if upstream ever changes.

## Configuration (`.env`)

Created from `.env.example` on first `./start.sh`. Keys: `CLAUDE_CREDENTIALS_FILE`
(seed path), `REFRESH_CHECK_INTERVAL`, `REFRESH_MARGIN`, `REFRESH_ON_START`, and
optional `CLAUDE_OAUTH_TOKEN_URL` / `CLAUDE_OAUTH_CLIENT_ID` overrides.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `refresher: refresh failed: HTTP 4xx` | Refresh token revoked/expired — re-`claude login` elsewhere and re-copy `secrets/.credentials.json`, then `./stop.sh -v && ./start.sh -d`. |
| Daemon: `Device not found` forever | Host not in BLE range, no BT adapter, or `bluetooth.service` down. |
| Daemon: D-Bus / `org.bluez` permission error | Uncomment `privileged: true` under the `daemon` service in `docker-compose.yml`. |
| Nothing connects, host is Windows/macOS | Expected — deploy on a Linux host. |

## ⚠️ Shared-account caveat (refresh-token rotation)

The refresher rotates your account's refresh token. If the **same** Claude login
is also used by Claude Code on your workstation, the two can fight: whichever
refreshes last may invalidate the other's refresh token, forcing a re-login on
the loser. For a clean 24/7 server, prefer a **dedicated Claude login** for the
device (seed `secrets/.credentials.json` from that account). If you only ever
use this login on the server, there's no conflict. Set `REFRESH_ON_START=false`
in `.env` if you'd rather it not rotate the token the moment it boots.

## No pairing needed

The data GATT characteristics are unencrypted, so the container connects without
OS pairing. (Don't pair the device's HID keyboard to a remote server — those
keypresses would land on the server, not your workstation.)
