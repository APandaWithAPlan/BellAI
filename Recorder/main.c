// Battery audio recorder, Pico W build.
//   core 1: PIO I2S capture -> AGC -> RAM ring                       (audio.c)
//   core 0: ring -> SD card in 60-minute WAV files; hourly Wi-Fi upload (sync.c)
// The radio is completely off (cyw43 deinitialised) except during an upload run.
#include <stdio.h>
#include <string.h>

#include "pico/stdlib.h"
#include "ff.h"
#include "f_util.h"

#include "config.h"
#include "audio.h"
#include "sync.h"
#include "provision.h"

static FATFS fs;
static FIL fil;
static bool file_open;
static char cur_name[32];
static uint32_t seq, file_bytes, fill;
static uint8_t stage[WRITE_BLOCK];
static absolute_time_t next_sync_flush, next_recover;

static void wav_header(uint8_t *h, uint32_t data_bytes) {
    #define LE32(o, v) do { h[o] = (v) & 255; h[o+1] = ((v) >> 8) & 255; h[o+2] = ((v) >> 16) & 255; h[o+3] = ((v) >> 24) & 255; } while (0)
    #define LE16(o, v) do { h[o] = (v) & 255; h[o+1] = ((v) >> 8) & 255; } while (0)
    memcpy(h, "RIFF", 4); LE32(4, 36u + data_bytes); memcpy(h + 8, "WAVEfmt ", 8);
    LE32(16, 16u); LE16(20, 1); LE16(22, 1); LE32(24, SAMPLE_RATE); LE32(28, SAMPLE_RATE * 2u);
    LE16(32, 2); LE16(34, 16); memcpy(h + 36, "data", 4); LE32(40, data_bytes);
}

static uint32_t next_seq(void) {
    uint32_t max = 0;
    DIR dir; FILINFO fno;
    if (f_opendir(&dir, "/rec") != FR_OK) return 1;
    while (f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
        unsigned s;
        if (sscanf(fno.fname, "rec_%u.wav", &s) == 1 && s > max) max = s;
    }
    f_closedir(&dir);
    return max + 1;
}

// The header always claims a full 3600 s. Finished files are exactly that size; a file cut short by
// power loss is simply shorter than its header says, and its real length is the file size.
static bool open_new(void) {
    char p[48];
    snprintf(cur_name, sizeof cur_name, "rec_%06lu.wav", (unsigned long)seq);
    snprintf(p, sizeof p, "/rec/%s", cur_name);
    uint8_t h[44]; UINT bw;
    wav_header(h, CHUNK_BYTES);
    if (f_open(&fil, p, FA_CREATE_ALWAYS | FA_WRITE) != FR_OK) { cur_name[0] = 0; return false; }
    if (f_write(&fil, h, 44, &bw) != FR_OK || bw != 44) { f_close(&fil); cur_name[0] = 0; return false; }
    file_open = true; file_bytes = 0;
    next_sync_flush = make_timeout_time_ms(30000);
    return true;
}

static bool mount_and_open(void) {
    FRESULT fr = f_mount(&fs, "", 1);
    if (fr != FR_OK) { printf("f_mount failed: %s (%d)\n", FRESULT_str(fr), (int)fr); return false; }
    f_mkdir("/rec");
    seq = next_seq();
    bool ok = open_new();
    if (!ok) printf("could not create /rec/rec_%06lu.wav\n", (unsigned long)seq);
    else printf("SD ok, recording to %s\n", cur_name);
    return ok;
}

static void sd_fault(void) {
    if (file_open) { f_close(&fil); file_open = false; }
    f_unmount("");
    cur_name[0] = 0;
    next_recover = make_timeout_time_ms(1000);
    printf("SD fault, will remount\n");
}

static void rotate(void) {
    f_close(&fil); file_open = false;
    seq++;
    if (!open_new()) { sd_fault(); return; }
    sync_request(0);                                  // a finished 60-minute chunk is waiting
}

static void flush_stage(void) {
    size_t off = 0;
    while (off < fill) {
        uint32_t w = fill - off;
        if (w > CHUNK_BYTES - file_bytes) w = CHUNK_BYTES - file_bytes;
        UINT bw;
        if (f_write(&fil, stage + off, w, &bw) != FR_OK || bw != w) { fill = 0; sd_fault(); return; }
        off += w; file_bytes += w;
        if (file_bytes >= CHUNK_BYTES) { rotate(); if (!file_open) { fill = 0; return; } }
    }
    fill = 0;
}

// Moves audio from the RAM ring to the SD card. Does at most one SD write per call so the
// upload state machine keeps getting time.
static void writer_pump(void) {
    if (!file_open) {
        if (absolute_time_diff_us(get_absolute_time(), next_recover) <= 0) {
            if (!mount_and_open()) next_recover = make_timeout_time_ms(2000);
        }
        return;
    }
    const uint8_t *p; size_t n;
    while ((n = audio_ring_peek(&p)) > 0) {
        size_t take = WRITE_BLOCK - fill;
        if (take > n) take = n;
        memcpy(stage + fill, p, take);
        fill += take;
        audio_ring_consume(take);
        if (fill == WRITE_BLOCK) { flush_stage(); return; }
    }
    if (file_open && absolute_time_diff_us(get_absolute_time(), next_sync_flush) <= 0) {
        if (f_sync(&fil) != FR_OK) sd_fault();         // makes the last ~30 s survive a power cut
        next_sync_flush = make_timeout_time_ms(30000);
    }
}

int main(void) {
    stdio_init_all();
    sleep_ms(3000);                                   // time to open the serial monitor
    printf("\nrecorder starting\n");
    sync_init();
    audio_init();

    while (!mount_and_open()) { printf("waiting for SD card\n"); sleep_ms(2000); }

    audio_start();                                    // SD is ready, so the first samples are not lost
    provision_begin();                                // Bluetooth setup window; uploads wait until it closes
    sync_request(30000);                              // upload any backlog from before a reboot

    uint32_t last_report = 0;
    for (;;) {
        writer_pump();
        provision_step(file_open);
        if (!provision_active()) sync_step(cur_name[0] ? cur_name : NULL);
        if (!sync_busy()) sleep_ms(2);
        uint32_t t = to_ms_since_boot(get_absolute_time());
        if (t - last_report > 60000) {
            last_report = t;
            if (audio_dropped_blocks()) printf("dropped blocks: %lu\n", (unsigned long)audio_dropped_blocks());
        }
    }
}
