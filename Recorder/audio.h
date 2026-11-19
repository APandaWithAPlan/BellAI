#pragma once
#include <stddef.h>
#include <stdint.h>

// Claims the PIO state machine and DMA channel (capture does not start yet).
void audio_init(void);
// Starts PIO + DMA and launches core 1, which runs the AGC and fills the ring buffer.
void audio_start(void);

// Single-producer (core 1) / single-consumer (core 0) byte ring of 16-bit mono PCM.
// peek returns a contiguous readable region (0 if empty); consume advances the read pointer.
size_t audio_ring_peek(const uint8_t **p);
void audio_ring_consume(size_t n);

uint32_t audio_dropped_blocks(void);   // 20 ms blocks dropped because the ring was full
