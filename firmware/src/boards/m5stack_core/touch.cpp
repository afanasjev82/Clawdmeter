#include "../../hal/touch_hal.h"
#include "board.h"

// The M5Stack Core has no touchscreen. The shared LVGL pointer indev still
// calls touch_hal_read() once per loop, so we report "never pressed". All UI
// interaction goes through the three physical buttons (input.cpp / power.cpp).

void touch_hal_init(void) {}

void touch_hal_read(uint16_t* x, uint16_t* y, bool* pressed) {
    *x = 0;
    *y = 0;
    *pressed = false;
}
