# Configurable screen auto-sleep — design

- **Date:** 2026-06-07
- **Status:** Approved (brainstorming), pending implementation plan
- **Scope:** Firmware (board-agnostic) + USB-serial daemon
- **Branch:** `m5stack-core`

## Background

The firmware already has an idle/sleep subsystem (`firmware/src/idle.cpp`,
`idle_cfg.h`): it smoothly PWM-fades the backlight to off after
`IDLE_TIMEOUT_MS` (currently 30 min) and wakes on any button press
(`idle_consume_wake_press()`). The fade machinery and wake-on-button already
work and are reused unchanged.

The deployed M5Stack on `crazybot` is "always on" for two reasons:
1. A change made last session: `ui_update()` calls `idle_note_activity()` on
   every data update for touchless boards. Data arrives every ~60 s, far under
   the 30 min timeout, so the timer never expires.
2. The timeout is a compile-time constant — not adjustable on a deployed device.

The device is a Core "Gray": an MPU-series accelerometer is present at I²C
`0x68` (confirmed by live scan), so shake-to-wake is physically possible — but
it is **out of scope for v1** (see Non-goals).

## Goals

- Configurable screen auto-sleep: backlight fades off after an idle timeout,
  measured from the **last button press** (classic screensaver).
- The timeout is settable at **runtime over USB serial** and **persisted in
  NVS** (survives reboots).
- `timeout = 0` disables sleep (always-on).
- Any button (A/B/C) wakes the panel (existing behavior, first press consumed
  as wake-only).
- Incoming usage data updates the numbers **silently** — it does not reset the
  timer and does not wake a sleeping panel.
- Configurable on the deployed device without stopping the daemon, by having the
  serial daemon push the timeout on connect from an env var.
- Board-agnostic (no `#ifdef BOARD_*`); the three Waveshare boards inherit the
  configurable timeout for free.

## Non-goals (deferred)

- **Shake-to-wake / IMU**: deferred to v2. Requires a vendored MPU6886/MPU9250
  reader, runtime `WHO_AM_I` detection (basic Cores have no IMU), shake
  detection, and threshold tuning. Key-press wake fully covers v1.
- **BLE-transport config parity**: v1 delivers config via the USB-serial daemon
  (the deployed transport). The BLE daemon could later write the same `sleep`
  command to the RX characteristic.
- Time-of-day scheduling (e.g. on during day, off at night).

## Behavior specification

- **Timer source:** `idle_tick()` fades out when `now - last_activity_ms >=
  timeout_ms` and `timeout_ms != 0`. `last_activity_ms` is reset only by button
  presses (via `idle_consume_wake_press()` in `main.cpp`), never by data.
- **`timeout_ms == 0`:** never fade out. If set to 0 while asleep/fading-out,
  wake immediately.
- **Wake:** any button press; first press from sleep is consumed as wake-only
  (unchanged).
- **Data while asleep:** `ui_update()` still updates labels and still
  auto-switches splash→usage on touchless boards (so content is correct on
  wake), but does **not** call `idle_note_activity()` and does not change
  brightness/sleep state.
- **Known trade-off:** a glance-only device will be dark most of the time, since
  glancing doesn't reset the timer. Mitigated by choosing a longer timeout, `0`
  (always-on), or shake-wake (v2).

## Firmware design (board-agnostic)

### `idle.{h,cpp}` — runtime timeout
- Replace compile-time use of `IDLE_TIMEOUT_MS` with a runtime `static uint32_t
  timeout_ms` initialized to the `idle_cfg.h` default.
- Add:
  - `void idle_set_timeout(uint32_t ms);` — set timeout; `0` = never sleep; if
    `0` and currently asleep/fading-out, trigger wake.
  - `uint32_t idle_get_timeout(void);`
- `idle_tick()` `STATE_AWAKE`: only fade out when `timeout_ms != 0 && elapsed >=
  timeout_ms`.
- `idle_cfg.h`: keep `IDLE_TIMEOUT_MS` as the **default**; add bounds
  `IDLE_TIMEOUT_MIN_S = 5`, `IDLE_TIMEOUT_MAX_S = 86400`.

### `sleep_cfg.{h,cpp}` — persistence (mirrors `brightness.cpp`)
- `void sleep_cfg_init(void);` — read NVS (namespace `"clawdmeter"`, key
  `"sleep_s"`); if present, `idle_set_timeout(seconds * 1000)`; log.
- `void sleep_cfg_set(uint32_t seconds);` — clamp (`0`, or `5..86400`); if
  different from the stored value, persist; then `idle_set_timeout()`. **Only
  writes NVS when the value changed** (avoids flash wear from repeated daemon
  sends).
- `uint32_t sleep_cfg_get(void);`
- Rationale for a separate module: matches the existing `brightness.cpp`
  pattern and keeps `idle.cpp` free of NVS/Preferences.

### `ui.cpp` — stop data from keeping the panel awake
- In `ui_update()`, remove the `idle_note_activity()` call added last session.
- **Keep** the touchless auto-switch splash→usage on first data.

### `main.cpp` — init + serial command
- Call `sleep_cfg_init()` in `setup()` (after `idle_init()` / `brightness_init()`).
- Extend `check_serial_cmd()` with a `sleep` command (see below). Existing `{…}`
  (usage JSON) and `screenshot` handling unchanged.

### Serial command
- `sleep <seconds>` → `sleep_cfg_set(n)`, reply `OK sleep=<n>`.
- `sleep 0` → reply `OK sleep=off`.
- `sleep` (no arg) → reply current value, e.g. `sleep=600` or `sleep=off`.
- Invalid/out-of-range → reply `ERR sleep`.
- Parsing: a line beginning with `sleep` is a command; a line beginning with
  `{` is usage data (unchanged).

## Daemon design (USB-serial)

`claude_usage_daemon_serial.py`:
- New env var `SCREEN_SLEEP_SECONDS` (optional).
- After opening the port and the post-reset boot delay, if `SCREEN_SLEEP_SECONDS`
  is set, write `sleep <n>\n` once and log `Set screen sleep: <n>s`.
- Idempotent across reconnects (firmware no-ops if unchanged).

`docker-compose.yml`:
- Pass `SCREEN_SLEEP_SECONDS: ${SCREEN_SLEEP_SECONDS:-}` to the `daemon-serial`
  service environment.

`.env.example`:
- Document `SCREEN_SLEEP_SECONDS` (e.g. `600`; empty = leave firmware default;
  `0` = never sleep).

## Defaults & bounds

- Firmware default (no NVS value, nothing sent): **1800 s (30 min)**.
- Clamp: `0` (off) or `5 … 86400` s.

## Edge cases

- Set timeout while asleep: `>0` just updates (panel stays asleep until a button
  wakes it); `0` wakes immediately.
- USB-charging keep-awake (`IDLE_SLEEP_WHEN_CHARGING=false` + `is_vbus_in()`):
  unchanged. On M5Stack `is_vbus_in()` is `false`, so it does not block sleep.
- NVS namespace `"clawdmeter"` is shared with `brightness` (`brt_idx`); keys are
  distinct (`sleep_s`).

## Testing / verification

1. Build `m5stack_core`; flash crazybot (`stop daemon-serial → esptool write
   0x10000 → start`).
2. Short-timeout check: set `SCREEN_SLEEP_SECONDS=30`, restart stack; daemon log
   shows the set; backlight fades out ~30 s after boot/last press.
3. Press A/B/C → panel wakes (fades in).
4. While asleep, daemon sends a usage update → panel stays dark; on next wake the
   numbers are current.
5. `SCREEN_SLEEP_SECONDS=0` → never sleeps.
6. Reboot crazybot/device → saved timeout still in effect (NVS).
7. Regression: build the three Waveshare envs to confirm no breakage.

## Files touched

- `firmware/src/idle.h`, `firmware/src/idle.cpp`
- `firmware/src/idle_cfg.h`
- `firmware/src/sleep_cfg.h`, `firmware/src/sleep_cfg.cpp` (new)
- `firmware/src/ui.cpp`
- `firmware/src/main.cpp`
- `daemon/claude_usage_daemon_serial.py`
- `daemon/docker-compose.yml`
- `daemon/.env.example`
