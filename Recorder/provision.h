#pragma once
#include <stdbool.h>

// Bluetooth setup window. For PROVISION_WINDOW_SECONDS after power-up the recorder advertises as "BellAI Recorder"
// and accepts one Wi-Fi network from the BellAI app, saved to /wifi.txt on the SD card (wifi_cfg.h). Then the radio is
// switched fully off again until the first upload. Power-cycle the recorder to open the window again.
void provision_begin(void);
// Call from the main loop. sd_ready: the card is mounted, so a received network can be saved.
void provision_step(bool sd_ready);
// True while Bluetooth owns the radio: uploads wait until it is off.
bool provision_active(void);
