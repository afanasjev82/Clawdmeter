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
