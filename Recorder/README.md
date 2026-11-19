# Battery audio recorder: Pico W + ICS-43434 + microSD

Records 16 kHz mono audio with software AGC, writes 60-minute WAV files (115.2 MB) to the SD card, and
once per file brings Wi-Fi up, uploads every finished file, deletes each one only after the receiver
confirms its length and CRC32, then turns the radio fully off again.

**Status:** bench-tested on a Pico W with 1-minute files. Confirmed on hardware: SD mounting and writing, mic
capture (the PIO program was also checked in a cycle-level simulation), finding the receiver on the network, and
uploads that the receiver verified by length and CRC32 before the recorder deleted its copy. **Not yet tested:**
60-minute files, battery operation and current draw, the Bluetooth Wi-Fi setup, and long unattended runs.
See "First bring-up" below.

## Wiring (GPIO numbers; wire by silkscreen label)
Physical pin numbers and a wiring check are in [PINOUT.md](PINOUT.md).

| ICS-43434 | Pico | | SD module | Pico |
|---|---|---|---|---|
| 3V | 3V3 (pin 36) | | 3V3 | 3V3 (pin 36) |
| GND | GND | | GND | GND |
| SEL | GND (left channel) | | CLK | GP18 |
| BCLK | GP14 | | MOSI | GP19 |
| LRCL | GP15 (must be BCLK + 1) | | MISO | GP16 |
| DOUT | GP13 | | CS | GP17 |

Power: Pimoroni Pico LiPo SHIM on the back of the Pico (uses VBUS/VSYS/GND only), LiPo in its JST-PH
socket. Check battery polarity first. Use a protected LiPo; the SHIM has no battery gauge.
Do not feed the mic or SD board from a 5 V rail.

## Build
```
git clone --depth 1 --branch 2.1.1 https://github.com/raspberrypi/pico-sdk.git
(cd pico-sdk && git submodule update --init --depth 1 lib/cyw43-driver lib/lwip lib/tinyusb)
# the SD library is already in lib/; if missing: git clone --branch v3.6.2 https://github.com/carlk3/no-OS-FatFS-SD-SDIO-SPI-RPi-Pico lib/no-OS-FatFS-SD-SDIO-SPI-RPi-Pico
cp config.example.h config.h        # then edit: Wi-Fi name and password, token (config.h is not tracked by git)
mkdir build && cd build && PICO_SDK_PATH=../pico-sdk cmake .. && make -j4
```
Hold BOOTSEL while plugging in USB and copy `build/recorder.uf2` to the RPI-RP2 drive.
(Pico 2 W: add `-DPICO_BOARD=pico2_w`; untested.)

Toolchain notes: use ARM's `arm-none-eabi` toolchain from developer.arm.com. Homebrew's `arm-none-eabi-gcc` formula has
no C library (no `stdio.h`), so Pico builds fail with it. RP2040 core stacks must fit the 4 KB scratch banks
(`PICO_STACK_SIZE=0x1000`, set in `CMakeLists.txt`), and `lwipopts.h` needs `MEMP_NUM_TCP_SEG` at least `TCP_SND_QUEUELEN`.

## Receiver and finding it
The recorder has no server address in its config. After joining Wi-Fi it scans its /24 subnet for `SERVER_PORT` (8080),
16 hosts at a time (a few seconds, about 15 at worst), and sends `GET /ping` to every host that accepts the connection. Only one that
answers `recorder-receiver` counts, so a router or other service on the same port is ignored. The address is remembered
until a connection to it fails, then it rescans once. Run a receiver on a computer on the same Wi-Fi with
`python3 receiver.py 8080`; the BellAI iOS app (`iOS-App/BellAI/Services/RecorderReceiver.swift`) speaks the same protocol:

| Request | Reply |
|---|---|
| `GET /ping` | `200`, body `recorder-receiver` |
| `POST /upload` with `X-Auth` (= `AUTH_TOKEN`), `X-Filename`, `Content-Length`, then the WAV | `200`, body `OK <bytes> <crc32 hex>` |

The recorder deletes its copy only if both numbers match what it sent. The scan only works if the router lets Wi-Fi
devices talk to each other (turn off client or AP isolation, and avoid guest networks).

## Wi-Fi setup from the BellAI app (Bluetooth)
For `PROVISION_WINDOW_SECONDS` (15) after power-up the recorder advertises as "BellAI Recorder" over BLE. In the app, Settings >
Clip-on recorder > Recorder's Wi-Fi, enter the network and tap Send. The recorder checks the app's password against `AUTH_TOKEN`,
saves the network to `/wifi.txt` on the SD card (line 1 name, line 2 password; you can also write it by hand), and switches the radio
off again. Each upload reads `/wifi.txt` first and falls back to `WIFI_SSID` / `WIFI_PASS` in `config.h`. Power-cycle to reopen the
window. The BLE link is unencrypted, so the password is sniffable while it is sent. Uploads wait until the window closes.
Not tested on hardware: BLE and Wi-Fi share the radio chip, and the stop/start between them is the risky part.

## First bring-up (do this in order)
1. In `config.h` set `CHUNK_SECONDS 60` so a "chunk" is one minute (1.9 MB) instead of an hour.
2. Power over USB, open the serial port (115200 baud; `screen /dev/tty.usbmodem* 115200` on a Mac, and quit it before
   flashing or the port stays busy): expect no "waiting for SD card" message. A 32 GB card must be FAT32. If it
   repeats `sd_init_medium: No disk...`, the card is not answering: check power, MISO/MOSI by label, and card seating.
   The firmware logs every Wi-Fi, scan and upload step, and the reason for any `sync failed`.
3. Talk near the mic for 2 minutes. After the first minute the device should connect to Wi-Fi, upload
   `rec_000001.wav`, print `uploaded and deleted`, and the file should appear on your computer and play.
4. Check `dropped blocks` never prints. If it does, the SD card is too slow or stalls: try another card.
5. Listen for clipping or pumping noise; adjust the AGC constants in `config.h`.
6. Only then set `CHUNK_SECONDS 3600`, connect the battery and measure current with a USB meter or PPK2.

## How it works
- **Core 1:** PIO state machine clocks the mic (BCLK = 1.024 MHz, 64 clocks per frame), DMA drops the left-channel
  words into an 8 KB ring, core 1 DC-blocks, applies the AGC per 20 ms block and pushes PCM into a 64 KB RAM ring
  (2 s of slack for SD write stalls). Whole blocks are dropped and counted if the ring ever overflows.
- **Core 0:** drains the ring to the SD card in 16 KB writes, syncs the file every 30 s, rotates at exactly 3600 s
  of samples (no gap), and runs the upload state machine in between SD writes so recording never pauses.
- **AGC:** DC blocker, target about -22 dBFS, up to +32 dB, fast attack / slow release, noise-floor gate so gain
  does not rise on room noise, soft limiter above 24000. It makes distant voices louder, not clearer: room noise
  and reverb are boosted too.
- **Upload:** `POST /upload` with `X-Auth` and `X-Filename`; the receiver replies `OK <bytes> <crc32hex>`. Backlog
  (up to 32 files) is sent oldest first. On any failure the file is kept and a retry is scheduled in 10 minutes.
- **WAV files:** the header claims a full 3600 s. A file cut short by power loss is shorter than its header says;
  its true length is the file size (the receiver or player can truncate).
- **Radio:** `cyw43_arch_deinit()` between runs, so the Wi-Fi chip is off while recording (lower power than modem sleep).

## Known gaps
- Still untested on hardware: 60-minute files, repeated Wi-Fi init/deinit over many hours, sustained SD writes at
  that length, the AGC on real speech (loud transients can reach full scale), and BLE with Wi-Fi sharing the radio chip.
- The mic wiring is the usual failure: a loose `DOUT`, `3V` or `GND` on the breadboard records stretches of exact silence.
- No battery monitoring: when the LiPo runs flat the device just stops. The last <=30 s of audio may be lost.
- No wall-clock timestamps: files are numbered, not dated.
- The iOS limitation still applies: iOS will not run a background server, so the app has to be open to receive
  (or use a receiver on an always-on machine). `receiver.py` is the protocol reference.
- Recording other people can require their consent depending on where you are.

## Power (estimate, unmeasured)
RP2040 at 125 MHz with core 0 mostly asleep, mic and SD idle: roughly 25-35 mA. The hourly upload (about 2 minutes
at 100-150 mA) adds about 4 mA on average. Expect around 30 hours from 1200 mAh; measure before relying on it.
Lowering the system clock is a possible later optimisation.
