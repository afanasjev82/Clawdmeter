#include "board.h"
#include <Arduino.h>
#include <Wire.h>

// Called once at the very start of setup(), before any HAL device init.
// No IO expander on this board; just bring up the shared I2C bus so the
// (deferred) IP5306 PMU and Gray-variant MPU are reachable later.
extern "C" void board_init(void) {
    Wire.begin(IIC_SDA, IIC_SCL);
}
