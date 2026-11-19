cmake_minimum_required(VERSION 3.13)

set(PICO_BOARD pico_w CACHE STRING "Board type")   # RP2040 Pico W. For Pico 2 W use pico2_w.
include(pico_sdk_import.cmake)

project(pico_recorder C CXX ASM)
if(NOT EXISTS ${CMAKE_CURRENT_LIST_DIR}/config.h)
    message(FATAL_ERROR "config.h is missing: copy config.example.h to config.h and fill in your Wi-Fi")
endif()
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

# FatFS + SD (SPI) driver, cloned into lib/ (see README)
add_subdirectory(lib/no-OS-FatFS-SD-SDIO-SPI-RPi-Pico/src build_sd)

add_executable(recorder
    main.c
    audio.c
    sync.c
    wifi_cfg.c
    provision.c
    hw_config.c
)

pico_generate_pio_header(recorder ${CMAKE_CURRENT_LIST_DIR}/i2s_in.pio)
target_include_directories(recorder PRIVATE ${CMAKE_CURRENT_LIST_DIR})

target_compile_definitions(recorder PRIVATE
    PICO_STACK_SIZE=0x1000              # RP2040 core stacks live in the two 4 KB scratch banks
    PICO_CORE1_STACK_SIZE=0x1000
    USE_PRINTF                          # SD library prints its own error details
    PICO_STDIO_USB_CONNECT_WAIT_TIMEOUT_MS=0
)

target_link_libraries(recorder
    pico_stdlib
    pico_multicore
    hardware_pio
    hardware_dma
    hardware_clocks
    pico_cyw43_arch_lwip_threadsafe_background
    pico_btstack_ble
    pico_btstack_cyw43
    no-OS-FatFS-SD-SDIO-SPI-RPi-Pico
)

pico_btstack_make_gatt_header(recorder PRIVATE ${CMAKE_CURRENT_LIST_DIR}/setup_service.gatt)

pico_enable_stdio_usb(recorder 1)
pico_enable_stdio_uart(recorder 0)
pico_add_extra_outputs(recorder)
