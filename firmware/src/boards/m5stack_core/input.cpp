#include "../../hal/input_hal.h"
#include "board.h"
#include <Arduino.h>

// Btn A (primary -> Space) and Btn C (secondary -> Shift+Tab). Btn B is the
// "PWR" button and lives in power.cpp. GPIO 37/38/39 are input-only with
// external pull-ups on the M5Stack Core, so INPUT (no internal pull) is correct
// and the buttons read LOW when pressed.
//
// Software debounce: raw state must be stable for DEBOUNCE_MS before we accept
// it. Prevents capacitive/inductive glitches on the input-only GPIOs from
// registering as phantom presses.

#define DEBOUNCE_MS 30

struct BtnDebounce {
    bool raw;
    bool out;
    uint32_t changed_ms;
};

static BtnDebounce s_primary   = {};
static BtnDebounce s_secondary = {};

static bool debounce(BtnDebounce* s, bool raw_now, uint32_t now) {
    if (raw_now != s->raw) {
        s->raw = raw_now;
        s->changed_ms = now;
    }
    if (now - s->changed_ms >= DEBOUNCE_MS) {
        s->out = s->raw;
    }
    return s->out;
}

void input_hal_init(void) {
    pinMode(BTN_BACK_GPIO, INPUT);
#if BOARD_HAS_SECONDARY_BUTTON
    pinMode(BTN_FWD_GPIO, INPUT);
#endif
}

bool input_hal_is_held(InputButton btn) {
    uint32_t now = millis();
    switch (btn) {
    case INPUT_BTN_PRIMARY:
        return debounce(&s_primary, digitalRead(BTN_BACK_GPIO) == LOW, now);
    case INPUT_BTN_SECONDARY:
#if BOARD_HAS_SECONDARY_BUTTON
        return debounce(&s_secondary, digitalRead(BTN_FWD_GPIO) == LOW, now);
#else
        return false;
#endif
    }
    return false;
}
