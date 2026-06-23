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
import threading
import time

import serial  # pyserial

from claude_usage_daemon import read_token, poll_api, log, POLL_INTERVAL

SERIAL_PORT = os.environ.get("SERIAL_PORT", "/dev/ttyUSB0")
SERIAL_BAUD = int(os.environ.get("SERIAL_BAUD", "115200"))

# Optional: push the screen auto-sleep timeout to the firmware on connect.
# Unset/blank → leave the firmware's saved value. Integer seconds; 0 = never.
_sleep_env = os.environ.get("SCREEN_SLEEP_SECONDS", "").strip()
SCREEN_SLEEP_SECONDS = int(_sleep_env) if _sleep_env.isdigit() else None

# Serializes access to the one pyserial handle. The reader thread and the main
# loop share it: concurrent readline()+write() on the same port raises
# SerialException ("multiple access on port") and used to kill the reader.
_io_lock = threading.Lock()


def open_serial() -> serial.Serial:
    """Open the port without asserting DTR/RTS, so we don't reset the ESP32 on
    every reconnect (one reset on the very first open is unavoidable)."""
    ser = serial.Serial()
    ser.port = SERIAL_PORT
    ser.baudrate = SERIAL_BAUD
    ser.timeout = 0.3  # short, so the reader releases _io_lock promptly for writes
    ser.dtr = False
    ser.rts = False
    ser.open()
    return ser


def _serial_reader(ser: serial.Serial) -> None:
    """Background thread: log every line the firmware prints to serial.
    Surfaces [boot] reset_reason, [idle] wake, ACK/NACK, and any crash output.

    Resilient by design: a transient SerialException (e.g. a read that races a
    write on the same handle) must NOT kill the thread, or async firmware output
    like '[idle] wake from ASLEEP' would silently stop being logged. We hold
    _io_lock around the actual read so it never collides with the writer."""
    while ser.is_open:
        try:
            with _io_lock:
                line = ser.readline()
        except Exception as e:
            log(f"[dev] reader hiccup: {e!r}")
            time.sleep(0.1)
            continue
        if line:
            text = line.decode(errors="replace").rstrip()
            if text:
                log(f"[dev] {text}")
        time.sleep(0.005)  # yield so a waiting writer can grab _io_lock


async def main() -> None:
    log(f"=== Claude Usage Tracker Daemon (USB serial {SERIAL_PORT}) ===")
    log(f"Poll interval: {POLL_INTERVAL}s")
    ser = None
    while True:
        try:
            if ser is None or not ser.is_open:
                ser = open_serial()
                log(f"Opened {SERIAL_PORT} @ {SERIAL_BAUD}")
                threading.Thread(target=_serial_reader, args=(ser,),
                                 daemon=True, name="serial-reader").start()
                time.sleep(2)  # let the device finish any reset-on-open boot
                if SCREEN_SLEEP_SECONDS is not None:
                    with _io_lock:
                        ser.write(f"sleep {SCREEN_SLEEP_SECONDS}\n".encode())
                        ser.flush()
                    log(f"Set screen sleep: {SCREEN_SLEEP_SECONDS}s")
            token = read_token()
            if not token:
                log("No token; skipping poll")
            else:
                payload = await poll_api(token)
                if payload is not None:
                    line = json.dumps(payload, separators=(",", ":")) + "\n"
                    with _io_lock:
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
