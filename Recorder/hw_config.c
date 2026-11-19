// SD card wiring for the no-OS-FatFS library. One card on SPI0.
#include "hw_config.h"
#include "config.h"

static spi_t spi = {
    .hw_inst   = spi0,
    .sck_gpio  = PIN_SD_SCK,
    .mosi_gpio = PIN_SD_MOSI,
    .miso_gpio = PIN_SD_MISO,
    .baud_rate = SD_BAUD_HZ,
};

static sd_spi_if_t spi_if = {
    .spi     = &spi,
    .ss_gpio = PIN_SD_CS,
};

static sd_card_t sd_card = {
    .type      = SD_IF_SPI,
    .spi_if_p  = &spi_if,
};

size_t sd_get_num() { return 1; }

sd_card_t *sd_get_by_num(size_t num) { return num == 0 ? &sd_card : NULL; }
