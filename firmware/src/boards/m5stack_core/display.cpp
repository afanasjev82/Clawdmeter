#include "../../hal/display_hal.h"
#include "board.h"
#include <Arduino.h>
#include <Arduino_GFX_Library.h>

// ILI9342C over hardware SPI. Unlike the AMOLED ports there is no panel-side
// brightness command — backlight is a plain GPIO, so we PWM it via LEDC and
// map the HAL's 0..255 level straight onto the duty cycle. No CPU rotation:
// the ILI9342 rotates natively and we run fixed landscape (rotation 0).

#define BL_PWM_FREQ  5000   // Hz
#define BL_PWM_RES   8      // bits -> 0..255 duty, matches the HAL level range
#define SPI_SPEED    40000000UL

static Arduino_DataBus* bus = nullptr;
static Arduino_GFX*     gfx = nullptr;

void display_hal_init(void) {
    bus = new Arduino_ESP32SPI(LCD_DC, LCD_CS, LCD_SCLK, LCD_MOSI, LCD_MISO);
    // (bus, rst, rotation, ips)
    gfx = new Arduino_ILI9342(bus, LCD_RESET, 0 /* landscape */, false /* IPS */);
}

void display_hal_begin(void) {
    gfx->begin(SPI_SPEED);
    gfx->fillScreen(0x0000);
    ledcAttach(LCD_BL, BL_PWM_FREQ, BL_PWM_RES);
    ledcWrite(LCD_BL, 200);
}

void display_hal_set_brightness(uint8_t level) {
    ledcWrite(LCD_BL, level);
}

void display_hal_fill_screen(uint16_t color) {
    if (gfx) gfx->fillScreen(color);
}

void display_hal_draw_bitmap(int32_t x, int32_t y, int32_t w, int32_t h,
                             const uint16_t* pixels) {
    if (gfx) gfx->draw16bitRGBBitmap(x, y, (uint16_t*)pixels, w, h);
}

void display_hal_tick(void) {
    // No rotation handling needed on this board.
}

void display_hal_round_area(int32_t* x1, int32_t* y1, int32_t* x2, int32_t* y2) {
    // ILI9342 accepts arbitrary CASET/PASET windows — no even-alignment
    // requirement. Leave LVGL's flush region untouched.
    (void)x1; (void)y1; (void)x2; (void)y2;
}
