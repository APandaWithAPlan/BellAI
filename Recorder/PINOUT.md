# BellAI Recorder Pinout

## Overview

How the ICS-43434 microphone and the microSD module are wired to the Pico W. The pins are set in `config.h` (`PIN_*`) and are GPIO numbers; the physical pin is the number on the Pico W's header, counted from the USB end: down the left side from 1 to 20, then up the right side from 21 to 40.

## Wiring

### SD card module (SPI0)

| SD board label | Pico GPIO | Physical pin |
| --- | --- | --- |
| `CLK` | GP18 | 24 |
| `MOSI` | GP19 | 25 |
| `MISO` | GP16 | 21 |
| `CS` | GP17 | 22 |
| `3V3` | 3V3(OUT) | 36 |
| `GND` | GND | 23 (or any GND) |

### ICS-43434 mic (I2S)

| Mic label | Pico GPIO | Physical pin |
| --- | --- | --- |
| `BCLK` | GP14 | 19 |
| `LRCL` | GP15 | 20 |
| `DOUT` | GP13 | 17 |
| `SEL` | GND (left channel) | 18 |
| `3V` | 3V3(OUT) | 36 |
| `GND` | GND | 18 (or any GND) |

> ⚠️ **Warning:** `LRCL` must be the GPIO right after `BCLK` (GP15 after GP14), because the PIO program clocks them as a pair. Moving `BCLK` moves `LRCL` with it.

### Power

| Part | Connection |
| --- | --- |
| Pico W over USB | USB for bench testing and flashing |
| Pimoroni Pico LiPo SHIM | On the back of the Pico W. It uses only `VBUS`, `VSYS` and `GND`, so no GPIO is taken |
| LiPo battery | The SHIM's JST-PH socket. Check the polarity first, and use a protected battery, because the SHIM has no battery gauge |

> ⚠️ **Warning:** The mic and the SD module are 3.3 V parts. Never feed them from a 5 V rail (`VBUS` or `VSYS`).

## Check the wiring

1. Wire by the silkscreen label on each board, not by wire color.
2. Power the Pico W over USB and open the serial port at 115200 baud: `screen /dev/tty.usbmodem* 115200`.
3. The log should not say `waiting for SD card`. If it repeats `sd_init_medium: No disk...`, check power, `MISO` and `MOSI` by label, and that the card is seated.
4. A loose `DOUT`, `3V` or `GND` on the breadboard records stretches of exact silence.
