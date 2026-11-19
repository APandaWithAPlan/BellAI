#pragma once
// ---- Edit these ----
#define WIFI_SSID    "YourWiFiName"
#define WIFI_PASS    "YourWiFiPassword"
#define SERVER_PORT  8080              // the recorder scans its Wi-Fi subnet for the receiver (receiver.py or the iOS app) on this port
#define AUTH_TOKEN   "change-me"          // also the password the BellAI app needs to change the Wi-Fi network over Bluetooth
#define PROVISION_WINDOW_SECONDS 15      // Bluetooth setup is open this long after power-up, longer while a phone is connected (see provision.c)

// ---- Pins (GPIO numbers, not header pin numbers) ----
#define PIN_I2S_DIN   13   // mic DOUT
#define PIN_I2S_BCLK  14   // mic BCLK; LRCL/WS MUST be the next GPIO (GP15)
#define PIN_SD_MISO   16   // SPI0
#define PIN_SD_CS     17
#define PIN_SD_SCK    18
#define PIN_SD_MOSI   19
#define SD_BAUD_HZ    12500000   // conservative for breadboard wiring; try 25000000 on a PCB

// ---- Audio ----
#define SAMPLE_RATE    16000                      // 16 kHz mono 16-bit = 115.2 MB/hour
#define CHUNK_SECONDS  3600   // 60-minute files. Use 60 for a bench test (1-minute files, 1.9 MB).
#define CHUNK_BYTES    ((uint32_t)SAMPLE_RATE * 2u * CHUNK_SECONDS)
#define BLOCK_SAMPLES  320                        // 20 ms AGC block
#define RING_BYTES     65536                      // ~2 s RAM buffer between capture (core 1) and SD writer (core 0); power of 2
#define WRITE_BLOCK    16384                      // SD write size

// ---- AGC (same tuning as the ESP32 build; levels are in 16-bit units) ----
#define AGC_TARGET_RMS      2600.0f   // about -22 dBFS
#define AGC_MAX_GAIN        40.0f     // about +32 dB
#define AGC_IDLE_GAIN       4.0f      // gain drifts here during silence
#define AGC_MIN_ACTIVE_RMS  60.0f     // below this, treated as noise: gain never rises

// ---- Upload ----
#define SEND_CHUNK        8192
#define MAX_BACKLOG_FILES 32
#define RETRY_DELAY_MS    (10u * 60u * 1000u)
