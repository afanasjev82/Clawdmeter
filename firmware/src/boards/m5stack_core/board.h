#pragma once

// M5Stack Core (basic / gray) — original ESP32, ILI9342C 320x240 TFT over SPI.
//
// Distinct from every other port in this repo: an original ESP32 (not S3/C6),
// an SPI TFT (not a QSPI AMOLED), no touchscreen, and no PSRAM. The HAL's
// existing no-PSRAM path (shared with the C6 env) and a no-op touch driver
// cover the gaps. Battery (IP5306) and IMU are deferred — see power.cpp/imu.cpp.
//
// Pins per the M5Stack Core schematic / moononournation Arduino_GFX dev config.

#define BOARD_NAME           "M5Stack Core"

// ---- Display geometry (landscape, buttons at the bottom edge) ----
#define LCD_WIDTH            320
#define LCD_HEIGHT           240

// ---- ILI9342C SPI display pins ----
#define LCD_DC               27
#define LCD_CS               14
#define LCD_SCLK             18
#define LCD_MOSI             23
#define LCD_MISO             19
#define LCD_RESET            33
#define LCD_BL               32    // backlight — PWM (LEDC) for brightness

// ---- I2C bus (MPU on "Gray" @ 0x68; non-I2C IP5306 PMU is NOT on the bus) ----
// Brought up for bus health. The Core's IP5306 ships in an I2C and a non-I2C
// variant; this unit has the non-I2C one (scan finds only 0x68), so there is no
// readable battery gauge — see power.cpp / BOARD_HAS_BATTERY below.
#define IIC_SDA              21
#define IIC_SCL              22

// ---- Touch ----
// No touch controller on this board. touch.cpp is a no-op stub; these are
// unused but kept so the shared/template contract stays uniform.
#define TP_INT               -1
#define TP_ADDR              0x00

// ---- Buttons ----
// Three front buttons (A/B/C left-to-right). A & C are HID keys; B acts as the
// "PWR" button (cycle screens / brightness / pairing) handled in power.cpp.
// GPIO 37/38/39 are input-only with external 10k pull-ups (no internal pulls).
#define BTN_BACK_GPIO        39    // Btn A (left)  — primary, Space (PTT)
#define BTN_FWD_GPIO         37    // Btn C (right) — secondary, Shift+Tab
#define BTN_PWR_GPIO         38    // Btn B (mid)   — cycle / pairing gesture

// ---- Capability flags ----
#define BOARD_HAS_SECONDARY_BUTTON 1   // Btn C
#define BOARD_HAS_ROTATION         0   // fixed landscape, no IMU
#define BOARD_HAS_IMU              0   // none on basic Core (Gray has MPU; deferred)
#define BOARD_HAS_BATTERY          0   // non-I2C IP5306 on this unit — unreadable (see power.cpp)
#define BOARD_HAS_IO_EXPANDER      0
