#pragma once
#include <stdbool.h>
#include <stdint.h>

void sync_init(void);
// Ask for an upload run after delay_ms. Safe to call repeatedly; runs are never overlapped.
void sync_request(uint32_t delay_ms);
// Call from the main loop. Never blocks for more than a few hundred ms (radio init/deinit);
// the file currently being recorded (basename, e.g. "rec_000012.wav") is never uploaded.
void sync_step(const char *current_name);
bool sync_busy(void);
