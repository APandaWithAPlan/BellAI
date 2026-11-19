#pragma once
#include <stdbool.h>

#define WIFI_SSID_MAX 32          // 802.11 limit
#define WIFI_PASS_MAX 63          // WPA2 passphrase limit

// Wi-Fi network to upload through. Read from /wifi.txt on the SD card (line 1 = name, line 2 = password) when it
// exists, so the BellAI app can set it over Bluetooth; otherwise the WIFI_SSID / WIFI_PASS in config.h.
// SD card only: call from core 0 with the card mounted, never from an interrupt or BLE callback.
void wifi_cfg_load(char ssid[WIFI_SSID_MAX + 1], char pass[WIFI_PASS_MAX + 1]);
bool wifi_cfg_save(const char *ssid, const char *pass);
