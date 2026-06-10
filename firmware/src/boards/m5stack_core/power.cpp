#include "../../hal/power_hal.h"
#include "board.h"
#include <Arduino.h>

// No usable battery gauge on this board. The Core's IP5306 PMU shipped in two
// variants; this unit has the NON-I2C version (an I2C scan finds only the IMU
// at 0x68, no PMU at 0x75), so the 110 mAh battery's charge level can't be read
// — and the Basic Core has no ADC voltage divider for it either. BOARD_HAS_BATTERY
// is therefore 0 and the UI hides the battery indicator.
//
// Btn B doubles as the "PWR" button. We poll it here and synthesize the same
// three edges the AXP PKEY produces on the other boards, so main.cpp's screen-
// cycle and hold-to-pair gesture work unchanged:
//   short tap            -> power_hal_pwr_pressed()       (cycle / brightness)
//   held >= LONG_MS      -> power_hal_pwr_long_pressed()  (arms pair gesture)
//   release after long   -> power_hal_pwr_released()      (completes pair gesture)

#define PWR_POLL_MS  20
#define LONG_MS      1500

static bool     btn_was       = false;
static uint32_t press_start   = 0;
static bool     long_emitted  = false;
static uint32_t last_poll_ms  = 0;

static bool short_flag    = false;
static bool long_flag     = false;
static bool released_flag = false;

void power_hal_init(void) {
    pinMode(BTN_PWR_GPIO, INPUT);   // input-only GPIO, external pull-up, active LOW
}

void power_hal_tick(void) {
    uint32_t now = millis();
    if (now - last_poll_ms < PWR_POLL_MS) return;
    last_poll_ms = now;

    bool pressed = digitalRead(BTN_PWR_GPIO) == LOW;

    if (pressed && !btn_was) {            // press edge
        press_start  = now;
        long_emitted = false;
    } else if (pressed && !long_emitted && (now - press_start >= LONG_MS)) {
        long_flag    = true;              // crossed the long-press threshold
        long_emitted = true;
    } else if (!pressed && btn_was) {     // release edge
        if (long_emitted) released_flag = true;          // long hold -> pair gesture
        else if (now - press_start >= 50) short_flag = true;  // quick tap, but not noise (<50ms)
    }
    btn_was = pressed;
}

int  power_hal_battery_pct(void) { return -1; }
bool power_hal_is_charging(void) { return false; }
bool power_hal_is_vbus_in(void)  { return false; }

bool power_hal_pwr_pressed(void) {
    if (short_flag) { short_flag = false; return true; }
    return false;
}

bool power_hal_pwr_long_pressed(void) {
    if (long_flag) { long_flag = false; return true; }
    return false;
}

bool power_hal_pwr_released(void) {
    if (released_flag) { released_flag = false; return true; }
    return false;
}
