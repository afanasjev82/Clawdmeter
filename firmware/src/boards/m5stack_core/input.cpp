#include "../../hal/input_hal.h"
#include "board.h"
#include <Arduino.h>

// Btn A (primary -> Space) and Btn C (secondary -> Shift+Tab). Btn B is the
// "PWR" button and lives in power.cpp. GPIO 37/38/39 are input-only with
// external pull-ups on the M5Stack Core, so INPUT (no internal pull) is correct
// and the buttons read LOW when pressed.

void input_hal_init(void) {
    pinMode(BTN_BACK_GPIO, INPUT);
#if BOARD_HAS_SECONDARY_BUTTON
    pinMode(BTN_FWD_GPIO, INPUT);
#endif
}

bool input_hal_is_held(InputButton btn) {
    switch (btn) {
    case INPUT_BTN_PRIMARY:
        return digitalRead(BTN_BACK_GPIO) == LOW;
    case INPUT_BTN_SECONDARY:
#if BOARD_HAS_SECONDARY_BUTTON
        return digitalRead(BTN_FWD_GPIO) == LOW;
#else
        return false;
#endif
    }
    return false;
}
