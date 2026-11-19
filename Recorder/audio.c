// Capture + AGC. PIO shifts 32-bit left-channel words into a DMA ring (RAW). Core 1 turns each
// 20 ms block into gain-corrected 16-bit PCM and pushes it into the byte ring read by core 0.
#include "audio.h"
#include "config.h"

#include <math.h>
#include <string.h>

#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/pio.h"
#include "hardware/dma.h"
#include "hardware/clocks.h"
#include "hardware/sync.h"
#include "i2s_in.pio.h"

#define RAW_WORDS 2048u                       // 8 KB DMA ring = 128 ms of slack
#define RAW_MASK  (RAW_WORDS - 1u)
#define RAW_RING_BITS 13                      // log2(RAW_WORDS * 4)

static uint32_t raw[RAW_WORDS] __attribute__((aligned(RAW_WORDS * 4)));

_Static_assert((RING_BYTES & (RING_BYTES - 1)) == 0, "RING_BYTES must be a power of two");
static uint8_t ring[RING_BYTES];
static volatile uint32_t ring_wr, ring_rd;    // free-running byte counters
static volatile uint32_t dropped;

static PIO  pio_inst = pio0;                  // the CYW43 driver prefers PIO1
static uint sm;
static uint dma_ch;

// ---------------------------------------------------------------- ring
static void __not_in_flash_func(ring_push)(const uint8_t *src, size_t n) {
    uint32_t wr = ring_wr, rd = ring_rd;
    if (RING_BYTES - (wr - rd) < n) { dropped++; return; }   // whole blocks only: keeps alignment
    size_t idx = wr & (RING_BYTES - 1);
    size_t first = RING_BYTES - idx;
    if (first > n) first = n;
    memcpy(ring + idx, src, first);
    memcpy(ring, src + first, n - first);
    __dmb();
    ring_wr = wr + (uint32_t)n;
}

size_t audio_ring_peek(const uint8_t **p) {
    uint32_t wr = ring_wr;
    __dmb();
    uint32_t rd = ring_rd;
    uint32_t avail = wr - rd;
    if (!avail) return 0;
    uint32_t idx = rd & (RING_BYTES - 1);
    uint32_t n = RING_BYTES - idx;
    if (n > avail) n = avail;
    *p = ring + idx;
    return n;
}

void audio_ring_consume(size_t n) {
    __dmb();
    ring_rd += (uint32_t)n;
}

uint32_t audio_dropped_blocks(void) { return dropped; }

// ---------------------------------------------------------------- AGC
static int32_t ybuf[BLOCK_SAMPLES];
static int16_t obuf[BLOCK_SAMPLES];
static int32_t dc;                            // DC blocker state (24-bit units)
static float gain = 6.0f, noise = 30.0f;
static int32_t gain_q16 = 6 << 16;

static inline int16_t soft_clip(int32_t v) {
    int32_t a = v < 0 ? -v : v;
    if (a > 24000) { a = 24000 + ((a - 24000) >> 2); if (a > 32767) a = 32767; }
    return (int16_t)(v < 0 ? -a : a);
}

static void __not_in_flash_func(process_block)(uint32_t rd) {
    uint64_t sumsq = 0;
    for (uint32_t i = 0; i < BLOCK_SAMPLES; i++) {
        int32_t s = (int32_t)raw[(rd + i) & RAW_MASK] >> 8;   // 24-bit signed mic sample
        dc += (s - dc) >> 8;                                  // one-pole DC blocker, ~10 Hz
        int32_t y = s - dc;
        ybuf[i] = y;
        int32_t y16 = y >> 8;
        sumsq += (uint32_t)(y16 * y16);
    }
    float rms = sqrtf((float)(uint32_t)(sumsq / BLOCK_SAMPLES));

    // Noise floor: falls fast, rises very slowly so speech does not become "noise".
    noise += (rms - noise) * (rms < noise ? 0.2f : 0.0005f);
    if (noise < 5.0f) noise = 5.0f;

    bool active = rms > noise * 2.5f && rms > AGC_MIN_ACTIVE_RMS;
    float target;
    if (active) {
        target = AGC_TARGET_RMS / rms;
        if (target < 1.0f) target = 1.0f;
        if (target > AGC_MAX_GAIN) target = AGC_MAX_GAIN;
    } else {
        target = gain + (AGC_IDLE_GAIN - gain) * 0.002f;      // hold, drift slowly, never pump up noise
    }
    float g1 = gain + (target - gain) * (target < gain ? 0.35f : 0.02f);   // fast attack, ~1-2 s release
    gain = g1;

    int32_t g1q = (int32_t)(g1 * 65536.0f);
    int32_t step = (g1q - gain_q16) / (int32_t)BLOCK_SAMPLES;             // linear ramp across the block
    int32_t g = gain_q16;
    for (uint32_t i = 0; i < BLOCK_SAMPLES; i++) {
        g += step;
        obuf[i] = soft_clip((int32_t)(((int64_t)ybuf[i] * g) >> 24));      // 24-bit * Q16 -> 16-bit
    }
    gain_q16 = g1q;
    ring_push((const uint8_t *)obuf, sizeof(obuf));
}

static void __not_in_flash_func(core1_main)(void) {
    uint32_t rd = 0;                                          // read index into raw[], in words
    for (;;) {
        // The DMA transfer count is ~2^32 words (about 3 days). If it ever completes, re-arm it;
        // the write address keeps its place and the PIO FIFO holds the samples in the meantime.
        if (!dma_channel_is_busy(dma_ch)) dma_channel_set_trans_count(dma_ch, 0xFFFFFFFFu, true);

        uint32_t wr = (dma_hw->ch[dma_ch].write_addr - (uint32_t)raw) >> 2;
        uint32_t avail = (wr - rd) & RAW_MASK;
        if (avail >= BLOCK_SAMPLES) {
            process_block(rd);
            rd = (rd + BLOCK_SAMPLES) & RAW_MASK;
        } else {
            sleep_us(500);
        }
    }
}

// ---------------------------------------------------------------- setup
void audio_init(void) {
    sm = pio_claim_unused_sm(pio_inst, true);
    uint offset = pio_add_program(pio_inst, &i2s_in_left_program);

    pio_gpio_init(pio_inst, PIN_I2S_DIN);
    pio_gpio_init(pio_inst, PIN_I2S_BCLK);
    pio_gpio_init(pio_inst, PIN_I2S_BCLK + 1);                // WS
    pio_sm_set_consecutive_pindirs(pio_inst, sm, PIN_I2S_BCLK, 2, true);
    pio_sm_set_consecutive_pindirs(pio_inst, sm, PIN_I2S_DIN, 1, false);

    pio_sm_config c = i2s_in_left_program_get_default_config(offset);
    sm_config_set_in_pins(&c, PIN_I2S_DIN);
    sm_config_set_sideset_pins(&c, PIN_I2S_BCLK);
    sm_config_set_in_shift(&c, false, true, 32);              // MSB first, autopush every 32 bits
    sm_config_set_fifo_join(&c, PIO_FIFO_JOIN_RX);            // 8-word RX FIFO
    sm_config_set_clkdiv(&c, (float)clock_get_hz(clk_sys) / (SAMPLE_RATE * 128.0f));
    pio_sm_init(pio_inst, sm, offset + i2s_in_left_offset_entry_point, &c);

    // Sample DOUT directly on the rising BCLK edge instead of through the 2-cycle input synchronizer.
    hw_set_bits(&pio_inst->input_sync_bypass, 1u << PIN_I2S_DIN);

    dma_ch = dma_claim_unused_channel(true);
    dma_channel_config dc_cfg = dma_channel_get_default_config(dma_ch);
    channel_config_set_transfer_data_size(&dc_cfg, DMA_SIZE_32);
    channel_config_set_read_increment(&dc_cfg, false);
    channel_config_set_write_increment(&dc_cfg, true);
    channel_config_set_dreq(&dc_cfg, pio_get_dreq(pio_inst, sm, false));
    channel_config_set_ring(&dc_cfg, true, RAW_RING_BITS);    // write address wraps inside raw[]
    dma_channel_configure(dma_ch, &dc_cfg, raw, &pio_inst->rxf[sm], 0xFFFFFFFFu, false);
}

void audio_start(void) {
    dma_channel_start(dma_ch);
    pio_sm_set_enabled(pio_inst, sm, true);
    multicore_launch_core1(core1_main);
}
