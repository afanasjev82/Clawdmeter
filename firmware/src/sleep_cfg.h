#pragma once
#include <stdint.h>

// Auto-sleep timeout, persisted to NVS and applied via idle_set_timeout().
// Value is in seconds; 0 means "never sleep". Mirrors brightness.{h,cpp}.
void     sleep_cfg_init(void);            // load saved timeout from NVS and apply
void     sleep_cfg_set(uint32_t seconds); // clamp (0, or 5..86400), persist-if-changed, apply
uint32_t sleep_cfg_get(void);             // current timeout in seconds (0 = off)
