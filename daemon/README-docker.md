# Clawdmeter daemon — Docker deployment

A Compose wrapper that runs the BLE daemon (`claude_usage_daemon.py`) in a
container, with `start`/`stop` scripts for Linux (`.sh`) and Windows (`.bat`).

## ⚠️ Must run on a native Linux host

Bluetooth LE in a container needs the **host's** networking and BlueZ stack
(reached over the system D-Bus socket). This works on a native Linux host only.
On **Docker Desktop (Windows/macOS)** the engine runs in a VM with no access to
the host Bluetooth radio — the daemon will scan forever and never connect. The
`.bat` scripts are only for building/managing the image on Windows.

Also remember **BLE is short-range (~10 m)** — the host must be physically near
the device and have a working Bluetooth adapter.

## Prerequisites (Ubuntu host)

- Docker Engine + Compose plugin.
- `bluetooth.service` running: `sudo systemctl enable --now bluetooth`.
- A Claude token on the host: run `claude login` (writes `~/.claude/.credentials.json`).

## Usage

```bash
cd daemon
./start.sh            # build + run in the foreground (Ctrl+C to stop)
./start.sh -d         # build + run detached (24/7)
docker compose logs -f
./stop.sh             # stop
./stop.sh --rmi       # stop and remove the built image
```

First run seeds `.env` from `.env.example`. Set `CLAUDE_CONFIG_DIR` there if your
token isn't at `$HOME/.claude`.

Expected log once connected:
```
[HH:MM:SS] Scanning for 'Clawdmeter' (8.0s)...
[HH:MM:SS] Found: XX:XX:XX:XX:XX:XX
[HH:MM:SS] Connected
[HH:MM:SS] Sending: {"s":...,"w":...}
```

## Notes

- The token dir is mounted **read-only**. If you re-`claude login` (token
  refresh), the container sees the new file on its next read; if usage stops
  with an HTTP 401, restart: `./stop.sh && ./start.sh -d`.
- No host pairing is needed — the data GATT characteristics are unencrypted.
  (The device's keyboard buttons would target this host if paired, which is
  usually not what you want on a remote server, so leave it unpaired.)
- If scanning fails with a D-Bus permission error, uncomment `privileged: true`
  in `docker-compose.yml`.
