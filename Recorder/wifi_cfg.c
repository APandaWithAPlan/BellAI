#include "wifi_cfg.h"
#include "config.h"

#include <stdio.h>
#include <string.h>

#include "ff.h"

#define WIFI_FILE "/wifi.txt"

static void copy(char *dst, size_t max, const char *src) {
    size_t n = strnlen(src, max);
    memcpy(dst, src, n);
    dst[n] = 0;
}

static void strip_eol(char *s) {
    size_t n = strlen(s);
    while (n && (s[n - 1] == '\n' || s[n - 1] == '\r')) s[--n] = 0;
}

void wifi_cfg_load(char ssid[WIFI_SSID_MAX + 1], char pass[WIFI_PASS_MAX + 1]) {
    copy(ssid, WIFI_SSID_MAX, WIFI_SSID);
    copy(pass, WIFI_PASS_MAX, WIFI_PASS);
    FIL f;
    if (f_open(&f, WIFI_FILE, FA_READ) != FR_OK) return;
    char s[WIFI_SSID_MAX + 3], p[WIFI_PASS_MAX + 3];       // room for the line ending and a terminator
    if (f_gets(s, sizeof s, &f)) {
        strip_eol(s);
        if (s[0]) {                                        // a file without a name is ignored, not used to join nothing
            copy(ssid, WIFI_SSID_MAX, s);
            p[0] = 0;
            if (f_gets(p, sizeof p, &f)) strip_eol(p);
            copy(pass, WIFI_PASS_MAX, p);
        }
    }
    f_close(&f);
}

// written to a temporary file first, so a power cut mid-save leaves the previous network in place
bool wifi_cfg_save(const char *ssid, const char *pass) {
    FIL f;
    if (f_open(&f, WIFI_FILE ".tmp", FA_CREATE_ALWAYS | FA_WRITE) != FR_OK) return false;
    int w = f_printf(&f, "%s\n%s\n", ssid, pass);
    FRESULT sync = f_sync(&f);
    f_close(&f);
    if (w < 0 || sync != FR_OK) return false;
    f_unlink(WIFI_FILE);
    return f_rename(WIFI_FILE ".tmp", WIFI_FILE) == FR_OK;
}
