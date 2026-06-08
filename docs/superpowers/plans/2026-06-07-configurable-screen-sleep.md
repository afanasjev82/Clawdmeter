# Configurable Screen Auto-Sleep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the backlight auto-sleep timeout runtime-configurable over USB serial (persisted in NVS), with classic-screensaver behavior (data updates silently, buttons wake), delivered to the deployed device by the serial daemon.

**Architecture:** Reuse the existing `idle.cpp` fade state machine; convert its compile-time timeout into a runtime value set via a new `sleep_cfg` module (mirrors `brightness.cpp`'s NVS pattern). A `sleep <n>` serial command drives it; the USB-serial daemon pushes the configured value on connect from `SCREEN_SLEEP_SECONDS`. Shake-wake (IMU) is deferred to v2.

**Tech Stack:** ESP32 Arduino (PlatformIO, `pioarduino`), LVGL 9, NVS via `Preferences.h`; Python daemon (`pyserial`, `httpx`) in Docker Compose on the Linux host `crazybot`.

**Conventions:**
- Branch: `m5stack-core`.
- **Do NOT add `Co-Authored-By` trailers to commits.**
- No firmware unit-test harness exists — verification is `pio run` (compile) + on-device serial/visual checks. Do not introduce a test framework.
- Build command (PowerShell, UTF-8 forced to avoid a cp1251 pio crash):
  `$env:PYTHONUTF8="1"; & "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e m5stack_core`
- Spec: `docs/superpowers/specs/2026-06-07-configurable-screen-sleep-design.md`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `firmware/src/idle_cfg.h` | Idle tunables (default timeout, bounds) | Modify |
| `firmware/src/idle.h` | Idle public API | Modify (add timeout getter/setter) |
| `firmware/src/idle.cpp` | Backlight fade state machine | Modify (runtime timeout) |
| `firmware/src/sleep_cfg.h` | Persisted sleep-timeout config API | Create |
| `firmware/src/sleep_cfg.cpp` | NVS load/save of timeout; applies via idle | Create |
| `firmware/src/ui.cpp` | UI; `ui_update()` data handling | Modify (drop keep-awake-on-data) |
| `firmware/src/main.cpp` | setup() wiring + serial command parser | Modify |
| `daemon/claude_usage_daemon_serial.py` | USB-serial transport | Modify (push sleep cfg on connect) |
| `daemon/docker-compose.yml` | Compose services | Modify (env var) |
| `daemon/.env.example` | Config template | Modify (document env var) |

---

## Task 1: Runtime timeout in the idle state machine

**Files:**
- Modify: `firmware/src/idle_cfg.h`
- Modify: `firmware/src/idle.h`
- Modify: `firmware/src/idle.cpp`

- [ ] **Step 1: Add bounds to `idle_cfg.h`**

Add these lines after the existing `#define IDLE_TIMEOUT_MS ...` line (keep `IDLE_TIMEOUT_MS` as the default):

```c
// Bounds for the runtime-configurable timeout (seconds). 0 = never sleep.
#define IDLE_TIMEOUT_MIN_S          5
#define IDLE_TIMEOUT_MAX_S          86400UL   // 24 h
```

- [ ] **Step 2: Declare the runtime API in `idle.h`**

Add after the existing `void idle_set_awake_brightness(uint8_t level);` declaration:

```c
// Runtime auto-sleep timeout. ms == 0 disables sleep (always-on); setting 0
// while the panel is dark wakes it. Persisted by sleep_cfg.{h,cpp}.
void     idle_set_timeout(uint32_t ms);
uint32_t idle_get_timeout(void);
```

- [ ] **Step 3: Add the runtime variable + functions in `idle.cpp`**

After the line `static uint8_t  awake_brightness = DISPLAY_DEFAULT_BRIGHTNESS;  // ...`, add:

```c
static uint32_t timeout_ms = IDLE_TIMEOUT_MS;   // runtime; sleep_cfg overrides
```

Then, immediately after the `idle_set_awake_brightness(...)` function definition, add:

```c
void idle_set_timeout(uint32_t ms) {
    timeout_ms = ms;
    // Disabling sleep while the panel is dark/fading-out should wake it.
    if (ms == 0 && (state == STATE_ASLEEP || state == STATE_FADING_OUT)) {
        last_activity_ms = millis();
        begin_fade(awake_brightness, last_activity_ms);
        state = STATE_FADING_IN;
    }
}

uint32_t idle_get_timeout(void) { return timeout_ms; }
```

- [ ] **Step 4: Use the runtime timeout in `idle_tick()`**

In `idle.cpp`, replace the `STATE_AWAKE` case body:

```c
    case STATE_AWAKE:
        if (now - last_activity_ms >= IDLE_TIMEOUT_MS) {
            begin_fade(0, now);
            state = STATE_FADING_OUT;
        }
        break;
```

with:

```c
    case STATE_AWAKE:
        if (timeout_ms != 0 && now - last_activity_ms >= timeout_ms) {
            begin_fade(0, now);
            state = STATE_FADING_OUT;
        }
        break;
```

- [ ] **Step 5: Compile**

Run: `$env:PYTHONUTF8="1"; & "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e m5stack_core`
Expected: `[SUCCESS]`.

- [ ] **Step 6: Commit**

```bash
git add firmware/src/idle_cfg.h firmware/src/idle.h firmware/src/idle.cpp
git commit -m "firmware(idle): runtime-settable auto-sleep timeout (0 = never)"
```

---

## Task 2: `sleep_cfg` module — NVS persistence (mirrors `brightness.cpp`)

**Files:**
- Create: `firmware/src/sleep_cfg.h`
- Create: `firmware/src/sleep_cfg.cpp`

- [ ] **Step 1: Create `firmware/src/sleep_cfg.h`**

```c
#pragma once
#include <stdint.h>

// Auto-sleep timeout, persisted to NVS and applied via idle_set_timeout().
// Value is in seconds; 0 means "never sleep". Mirrors brightness.{h,cpp}.
void     sleep_cfg_init(void);            // load saved timeout from NVS and apply
void     sleep_cfg_set(uint32_t seconds); // clamp (0, or 5..86400), persist-if-changed, apply
uint32_t sleep_cfg_get(void);             // current timeout in seconds (0 = off)
```

- [ ] **Step 2: Create `firmware/src/sleep_cfg.cpp`**

```c
#include "sleep_cfg.h"
#include "idle.h"
#include "idle_cfg.h"
#include <Preferences.h>
#include <Arduino.h>

// Default mirrors the compile-time idle default until NVS / a serial command
// overrides it.
static uint32_t cur_seconds = IDLE_TIMEOUT_MS / 1000UL;

static uint32_t clamp_seconds(uint32_t s) {
    if (s == 0) return 0;                                  // disabled
    if (s < IDLE_TIMEOUT_MIN_S) return IDLE_TIMEOUT_MIN_S;
    if (s > IDLE_TIMEOUT_MAX_S) return IDLE_TIMEOUT_MAX_S;
    return s;
}

void sleep_cfg_init(void) {
    Preferences prefs;
    prefs.begin("clawdmeter", true);
    uint32_t saved = prefs.getULong("sleep_s", 0xFFFFFFFFUL);  // sentinel = unset
    prefs.end();

    if (saved != 0xFFFFFFFFUL) cur_seconds = clamp_seconds(saved);
    idle_set_timeout(cur_seconds * 1000UL);
    Serial.printf("Sleep init: timeout=%lus%s\n",
        (unsigned long)cur_seconds, cur_seconds ? "" : " (off)");
}

void sleep_cfg_set(uint32_t seconds) {
    uint32_t s = clamp_seconds(seconds);
    if (s != cur_seconds) {                 // only touch flash when it changed
        cur_seconds = s;
        Preferences prefs;
        prefs.begin("clawdmeter", false);
        prefs.putULong("sleep_s", s);
        prefs.end();
    }
    idle_set_timeout(s * 1000UL);
}

uint32_t sleep_cfg_get(void) { return cur_seconds; }
```

- [ ] **Step 3: Compile**

Run: `$env:PYTHONUTF8="1"; & "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e m5stack_core`
Expected: `[SUCCESS]` (the module compiles even though it isn't called yet — `build_src_filter` includes all `src/*.cpp`).

- [ ] **Step 4: Commit**

```bash
git add firmware/src/sleep_cfg.h firmware/src/sleep_cfg.cpp
git commit -m "firmware(sleep_cfg): NVS-persisted auto-sleep timeout"
```

---

## Task 3: Stop incoming data from keeping the panel awake

**Files:**
- Modify: `firmware/src/ui.cpp` (the `ui_update()` touchless block)

- [ ] **Step 1: Edit the touchless block in `ui_update()`**

Replace:

```c
    if (!board_caps().has_touch) {
        idle_note_activity();
        if (current_screen == SCREEN_SPLASH) ui_show_screen(SCREEN_USAGE);
    }
```

with:

```c
    if (!board_caps().has_touch) {
        // Surface usage on first data so the display is hands-off after a
        // reboot, but do NOT treat data as activity — the panel sleeps on the
        // idle timer regardless of data flow (classic screensaver).
        if (current_screen == SCREEN_SPLASH) ui_show_screen(SCREEN_USAGE);
    }
```

- [ ] **Step 2: Compile**

Run: `$env:PYTHONUTF8="1"; & "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e m5stack_core`
Expected: `[SUCCESS]`. (`idle.h` is already included in `ui.cpp`; the now-unused include stays — `idle_note_activity` is still declared, just no longer called here.)

- [ ] **Step 3: Commit**

```bash
git add firmware/src/ui.cpp
git commit -m "firmware(ui): data no longer resets the idle/sleep timer"
```

---

## Task 4: Wire init + the `sleep` serial command into `main.cpp`

**Files:**
- Modify: `firmware/src/main.cpp`

- [ ] **Step 1: Include the new module**

In `main.cpp`, add to the existing app-header include group (next to `#include "brightness.h"`):

```c
#include "sleep_cfg.h"
```

- [ ] **Step 2: Initialize it in `setup()`**

Find `brightness_init();` in `setup()` and add the line right after it:

```c
    sleep_cfg_init();   // load saved auto-sleep timeout and apply to idle
```

- [ ] **Step 3: Add the command handler above `check_serial_cmd()`**

Immediately before `static void check_serial_cmd() {`, add:

```c
// Handle a "sleep" serial command. `arg` points just past "sleep".
//   "sleep"        → query: prints "sleep=<n>" or "sleep=off"
//   "sleep <n>"    → set timeout to n seconds (0 = never sleep)
static void handle_sleep_cmd(const char* arg) {
    while (*arg == ' ') arg++;
    if (*arg == '\0') {                         // query
        uint32_t s = sleep_cfg_get();
        if (s) Serial.printf("sleep=%lu\n", (unsigned long)s);
        else   Serial.println("sleep=off");
        return;
    }
    char* end = nullptr;
    long val = strtol(arg, &end, 10);
    if (end == arg || val < 0) { Serial.println("ERR sleep"); return; }
    sleep_cfg_set((uint32_t)val);
    uint32_t s = sleep_cfg_get();
    if (s) Serial.printf("OK sleep=%lu\n", (unsigned long)s);
    else   Serial.println("OK sleep=off");
}
```

- [ ] **Step 4: Dispatch it inside `check_serial_cmd()`**

Replace the command-dispatch block:

```c
            if (cmd_buf[0] == '{')
                Serial.println(apply_usage(cmd_buf) ? "ACK" : "NACK");
            else if (strcmp(cmd_buf, "screenshot") == 0)
                send_screenshot();
```

with:

```c
            if (cmd_buf[0] == '{')
                Serial.println(apply_usage(cmd_buf) ? "ACK" : "NACK");
            else if (strncmp(cmd_buf, "sleep", 5) == 0)
                handle_sleep_cmd(cmd_buf + 5);
            else if (strcmp(cmd_buf, "screenshot") == 0)
                send_screenshot();
```

- [ ] **Step 5: Compile**

Run: `$env:PYTHONUTF8="1"; & "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e m5stack_core`
Expected: `[SUCCESS]`. (`strtol`/`strncmp` come from `<Arduino.h>`, already included.)

- [ ] **Step 6: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "firmware(main): 'sleep <n>' serial command + sleep_cfg init"
```

---

## Task 5: Regression-build all board envs

Confirms the board-agnostic changes don't break the other three ports.

**Files:** none (build only)

- [ ] **Step 1: Build each env**

Run each (UTF-8 forced):
```
& "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e waveshare_amoled_216
& "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e waveshare_amoled_18
& "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run -d "w:\Work\Projects\Clawdmeter\firmware" -e waveshare_amoled_216_c6
```
Expected: `[SUCCESS]` for all three. (No commit — build verification only.)

---

## Task 6: Flash crazybot's device and verify on hardware

The device is on `crazybot` at `/dev/ttyUSB0`; the `daemon-serial` container holds the port, so stop it first. All commands run over `ssh -o BatchMode=yes afanasjev@crazybot`.

**Files:** none (deploy/verify)

- [ ] **Step 1: Copy the freshly built firmware to crazybot**

From the Windows host:
```
scp -o BatchMode=yes "w:\Work\Projects\Clawdmeter\firmware\.pio\build\m5stack_core\firmware.bin" afanasjev@crazybot:/tmp/firmware.bin
```
Expected: completes with no error.

- [ ] **Step 2: Stop the daemon, flash app partition, restart daemon**

```
ssh -o BatchMode=yes afanasjev@crazybot 'docker stop clawdmeter-daemon-serial; docker run --rm --device /dev/ttyUSB0 -v /tmp:/work python:3.12-slim sh -c "pip install -q esptool==4.8.1 && esptool.py --chip esp32 --port /dev/ttyUSB0 --baud 460800 --before default_reset --after hard_reset write_flash 0x10000 /work/firmware.bin"; docker start clawdmeter-daemon-serial'
```
Expected: `Hash of data verified.` then `Hard resetting`.

- [ ] **Step 3: Verify the `sleep` command end-to-end (short timeout)**

Stop the daemon to free the port, then drive the device directly with a one-off container:
```
ssh -o BatchMode=yes afanasjev@crazybot 'docker stop clawdmeter-daemon-serial; docker run --rm --device /dev/ttyUSB0 clawdmeter-daemon:latest python -c "
import serial,time
s=serial.Serial(); s.port=\"/dev/ttyUSB0\"; s.baudrate=115200; s.timeout=1
s.dtr=False; s.rts=False; s.open(); time.sleep(2)
s.reset_input_buffer()
s.write(b\"sleep 15\n\"); s.flush(); time.sleep(1)
print(\"set reply:\", s.read(60))
s.write(b\"sleep\n\"); s.flush(); time.sleep(1)
print(\"query reply:\", s.read(60))
s.close()
"'
```
Expected: `set reply: b'OK sleep=15\r\n'` and `query reply: b'sleep=15\r\n'`.

- [ ] **Step 4: Visual check (manual)**

With the device idle (no button presses), confirm the backlight fades to black ~15 s after the last reset/press, then press **Btn A/B/C** and confirm it fades back in. Confirm a `sleep 0` reply of `OK sleep=off` keeps it on. (This step needs eyes on the device next to crazybot.)

- [ ] **Step 5: Restart the daemon**

```
ssh -o BatchMode=yes afanasjev@crazybot 'docker start clawdmeter-daemon-serial'
```
Expected: container `Up`. (No commit — verification only. The `sleep 15` is now saved in NVS; Task 9 sets the real value.)

---

## Task 7: Daemon pushes `SCREEN_SLEEP_SECONDS` on connect

**Files:**
- Modify: `daemon/claude_usage_daemon_serial.py`

- [ ] **Step 1: Parse the env var (top of file, near `SERIAL_PORT`)**

After the `SERIAL_BAUD = ...` line, add:

```python
# Optional: push the screen auto-sleep timeout to the firmware on connect.
# Unset/blank → leave the firmware's saved value. Integer seconds; 0 = never.
_sleep_env = os.environ.get("SCREEN_SLEEP_SECONDS", "").strip()
SCREEN_SLEEP_SECONDS = int(_sleep_env) if _sleep_env.isdigit() else None
```

- [ ] **Step 2: Send it once after the port opens**

In `main()`, inside the `if ser is None or not ser.is_open:` block, after the existing `time.sleep(2)  # let the device finish any reset-on-open boot` line, add:

```python
                if SCREEN_SLEEP_SECONDS is not None:
                    ser.write(f"sleep {SCREEN_SLEEP_SECONDS}\n".encode())
                    ser.flush()
                    log(f"Set screen sleep: {SCREEN_SLEEP_SECONDS}s")
```

- [ ] **Step 3: Syntax check**

Run: `python -m py_compile daemon/claude_usage_daemon_serial.py`
Expected: no output (exit 0).

- [ ] **Step 4: Commit**

```bash
git add daemon/claude_usage_daemon_serial.py
git commit -m "daemon(serial): push SCREEN_SLEEP_SECONDS to firmware on connect"
```

---

## Task 8: Expose the env var in Compose + `.env.example`

**Files:**
- Modify: `daemon/docker-compose.yml`
- Modify: `daemon/.env.example`

- [ ] **Step 1: Add the env to the `daemon-serial` service**

In `daemon/docker-compose.yml`, under `daemon-serial:` → `environment:`, add a line alongside the existing `SERIAL_PORT`/`SERIAL_BAUD`:

```yaml
      SCREEN_SLEEP_SECONDS: ${SCREEN_SLEEP_SECONDS:-}
```

- [ ] **Step 2: Document it in `.env.example`**

In `daemon/.env.example`, after the `SERIAL_BAUD=115200` line, add:

```bash
# Screen auto-sleep timeout in seconds, pushed to the device on connect.
# Blank = leave the device's saved value; 0 = never sleep. e.g. 600 = 10 min.
SCREEN_SLEEP_SECONDS=
```

- [ ] **Step 3: Validate compose config**

Run: `cd daemon && CLAUDE_CREDENTIALS_FILE=./secrets/x docker compose --profile usb config`
Expected: prints the resolved config with no error; `daemon-serial` shows `SCREEN_SLEEP_SECONDS`.

- [ ] **Step 4: Commit**

```bash
git add daemon/docker-compose.yml daemon/.env.example
git commit -m "daemon(compose): SCREEN_SLEEP_SECONDS env for the usb profile"
```

---

## Task 9: Deploy to crazybot and end-to-end verify

**Files:** none (deploy/verify). Pushes the branch and applies on the live host.

- [ ] **Step 1: Push the branch**

```bash
git push origin m5stack-core
```
Expected: refs updated (the firmware was already flashed in Task 6; this ships the daemon/compose changes).

- [ ] **Step 2: Pull + set the real timeout + restart on crazybot**

Choose the desired value (example: 600 s). Append it to `.env` and restart the usb stack:
```
ssh -o BatchMode=yes afanasjev@crazybot 'cd ~/Clawdmeter && git pull --ff-only origin m5stack-core && cd daemon && grep -q "^SCREEN_SLEEP_SECONDS=" .env && sed -i "s/^SCREEN_SLEEP_SECONDS=.*/SCREEN_SLEEP_SECONDS=600/" .env || echo "SCREEN_SLEEP_SECONDS=600" >> .env; bash start.sh -t usb -d'
```
Expected: stack rebuilds/recreates; ends with `Up`.

- [ ] **Step 3: Confirm the daemon pushed the setting**

```
ssh -o BatchMode=yes afanasjev@crazybot 'docker logs --since 30s clawdmeter-daemon-serial 2>&1 | grep -E "Set screen sleep|Sending"'
```
Expected: a line `Set screen sleep: 600s` and the periodic `Sending: {...}`.

- [ ] **Step 4: Final visual confirmation (manual)**

Confirm the device shows usage, stays awake (no 15 s sleep from Task 6's test value — it's now 600 s), and that it fades off after 10 min idle and wakes on a button press. Adjust `SCREEN_SLEEP_SECONDS` in `.env` and re-run Step 2 to tune.

---

## Notes / Out of scope

- **Shake-to-wake (IMU)** and **BLE-transport config parity** are deferred (see spec Non-goals).
- NVS namespace `"clawdmeter"` is shared with brightness (`brt_idx`); the sleep key is `sleep_s` (distinct). No migration needed.
