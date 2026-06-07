#!/usr/bin/env python3
"""USB-serial transport for the Clawdmeter daemon (no Bluetooth).

Fallback for hosts without a working BLE adapter: poll the Claude API exactly
like the BLE daemon, but write the JSON payload down the device's USB serial
line (the CP2104) instead of over a GATT characteristic. The firmware accepts a
"{...}" line on its serial console and renders it identically to a BLE update.

Reuses read_token() + poll_api() from claude_usage_daemon so the token/API
logic lives in one place.
"""

import asyncio
import json
import os
import sys
import time

import serial  # pyserial

from claude_usage_daemon import read_token, poll_api, log, POLL_INTERVAL

SERIAL_PORT = os.environ.get("SERIAL_PORT", "/dev/ttyUSB0")
SERIAL_BAUD = int(os.environ.get("SERIAL_BAUD", "115200"))


def open_serial() -> serial.Serial:
    """Open the port without asserting DTR/RTS, so we don't reset the ESP32 on
    every reconnect (one reset on the very first open is unavoidable)."""
    ser = serial.Serial()
    ser.port = SERIAL_PORT
    ser.baudrate = SERIAL_BAUD
    ser.timeout = 1
    ser.dtr = False
    ser.rts = False
    ser.open()
    return ser


async def main() -> None:
    log(f"=== Claude Usage Tracker Daemon (USB serial {SERIAL_PORT}) ===")
    log(f"Poll interval: {POLL_INTERVAL}s")
    ser = None
    while True:
        try:
            if ser is None or not ser.is_open:
                ser = open_serial()
                log(f"Opened {SERIAL_PORT} @ {SERIAL_BAUD}")
                time.sleep(2)  # let the device finish any reset-on-open boot
            token = read_token()
            if not token:
                log("No token; skipping poll")
            else:
                payload = await poll_api(token)
                if payload is not None:
                    line = json.dumps(payload, separators=(",", ":")) + "\n"
                    ser.write(line.encode())
                    ser.flush()
                    log(f"Sending: {line.strip()}")
        except serial.SerialException as e:
            log(f"Serial error: {e}; will reopen")
            try:
                if ser:
                    ser.close()
            except Exception:
                pass
            ser = None
        except Exception as e:  # never let the loop die
            log(f"loop error: {e}")
        await asyncio.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
