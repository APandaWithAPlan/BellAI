// Wi-Fi setup over Bluetooth LE, so the network can be changed from the BellAI app without reflashing.
//
// GATT service 6F1A0001-7B3C-4E8A-9D52-0C3E1B7A4F10, one write-only characteristic 6F1A0002-... taking one message:
//     [len][AUTH_TOKEN] [len][SSID] [len][password]        each len is one byte, then that many bytes
// A wrong AUTH_TOKEN is answered with ATT error 0x80 and nothing is stored. The link is not
// encrypted, so the network password is readable by anyone sniffing Bluetooth during the few seconds it is sent;
// the window is short and only open after power-up for that reason.
//
// The write callback runs in BTstack's context, where the SD card must not be touched, so it only stages the
// message; provision_step() saves it from the main loop.
#include "provision.h"
#include "config.h"
#include "wifi_cfg.h"
#include "sync.h"

#include <stdio.h>
#include <string.h>

#include "btstack.h"
#include "pico/cyw43_arch.h"
#include "pico/stdlib.h"
#include "setup_service.h"      // generated from setup_service.gatt

// an application error code (0x80-0x9F). iOS reacts to the standard authentication/authorization codes by trying to pair, and hangs when the recorder has no pairing
#define ATT_ERROR_WRONG_PASSWORD 0x80

#define MAX_MESSAGE (3 + sizeof(AUTH_TOKEN) + WIFI_SSID_MAX + WIFI_PASS_MAX)
#define CONNECTED_GRACE_MS 60000
#define SAVED_LINGER_MS 3000    // lets the app see the write confirmed before the radio goes away

static const uint8_t adv_data[] = {
    0x02, BLUETOOTH_DATA_TYPE_FLAGS, 0x06,
    0x11, BLUETOOTH_DATA_TYPE_COMPLETE_LIST_OF_128_BIT_SERVICE_CLASS_UUIDS,
    0x10, 0x4F, 0x7A, 0x1B, 0x3E, 0x0C, 0x52, 0x9D, 0x8A, 0x4E, 0x3C, 0x7B, 0x01, 0x00, 0x1A, 0x6F,   // service UUID, little endian
};
static const uint8_t scan_data[] = {
    0x10, BLUETOOTH_DATA_TYPE_COMPLETE_LOCAL_NAME, 'B', 'e', 'l', 'l', 'A', 'I', ' ', 'R', 'e', 'c', 'o', 'r', 'd', 'e', 'r',
};

static btstack_packet_callback_registration_t hci_callback;
static volatile bool active, connected;
static volatile bool staged;                       // a checked network is waiting for the main loop to save it
static char staged_ssid[WIFI_SSID_MAX + 1], staged_pass[WIFI_PASS_MAX + 1];
static uint32_t deadline_ms, linger_until_ms;

static uint32_t now_ms(void) { return to_ms_since_boot(get_absolute_time()); }

static bool same_token(const uint8_t *p, size_t n) {
    static const char token[] = AUTH_TOKEN;
    size_t len = sizeof token - 1;
    uint8_t diff = n != len;
    for (size_t i = 0; i < len; i++) diff |= (i < n ? p[i] : 0) ^ (uint8_t)token[i];
    return diff == 0;
}

static int check_write(hci_con_handle_t con, uint16_t handle, uint16_t mode, uint16_t offset, uint8_t *buf, uint16_t size) {
    (void)con;
    printf("setup: write handle 0x%04x mode %u offset %u size %u\n", handle, mode, offset, size);
    if (handle != ATT_CHARACTERISTIC_6F1A0002_7B3C_4E8A_9D52_0C3E1B7A4F10_01_VALUE_HANDLE) return 0;
    if (offset != 0) return ATT_ERROR_ATTRIBUTE_NOT_LONG;      // the app sends it in one write
    if (staged) return ATT_ERROR_UNLIKELY_ERROR;               // the previous one is not saved yet

    // [len][token][len][ssid][len][password], nothing before, between or after
    uint16_t at = 0;
    const uint8_t *field[3];
    uint8_t len[3];
    for (int i = 0; i < 3; i++) {
        if (at >= size) return ATT_ERROR_INVALID_ATTRIBUTE_VALUE_LENGTH;
        len[i] = buf[at++];
        if (len[i] > size - at) return ATT_ERROR_INVALID_ATTRIBUTE_VALUE_LENGTH;
        field[i] = buf + at;
        at += len[i];
    }
    if (at != size) return ATT_ERROR_INVALID_ATTRIBUTE_VALUE_LENGTH;
    if (!same_token(field[0], len[0])) {
        printf("setup: password has %u characters, AUTH_TOKEN has %u\n", len[0], (unsigned)(sizeof AUTH_TOKEN - 1));
        return ATT_ERROR_WRONG_PASSWORD;
    }
    // the file is line based, so a name or password with a line break (or a NUL) can't be stored
    if (len[1] == 0 || len[1] > WIFI_SSID_MAX || len[2] > WIFI_PASS_MAX) return ATT_ERROR_VALUE_NOT_ALLOWED;
    for (int i = 1; i < 3; i++)
        for (uint8_t k = 0; k < len[i]; k++)
            if (field[i][k] == '\n' || field[i][k] == '\r' || field[i][k] == 0) return ATT_ERROR_VALUE_NOT_ALLOWED;

    memcpy(staged_ssid, field[1], len[1]); staged_ssid[len[1]] = 0;
    memcpy(staged_pass, field[2], len[2]); staged_pass[len[2]] = 0;
    staged = true;
    printf("setup: message accepted for \"%s\"\n", staged_ssid);
    return 0;
}

static int on_write(hci_con_handle_t con, uint16_t handle, uint16_t mode, uint16_t offset, uint8_t *buf, uint16_t size) {
    int r = check_write(con, handle, mode, offset, buf, size);
    if (r) printf("setup: write refused, ATT error 0x%02x\n", r);
    return r;
}

static void on_hci(uint8_t type, uint16_t channel, uint8_t *packet, uint16_t size) {
    (void)channel; (void)size;
    if (type != HCI_EVENT_PACKET) return;
    switch (hci_event_packet_get_type(packet)) {
    case BTSTACK_EVENT_STATE:
        if (btstack_event_state_get_state(packet) == HCI_STATE_WORKING) {
            bd_addr_t none = {0};
            gap_advertisements_set_params(160, 160, 0, 0, none, 0x07, 0x00);   // 100 ms, connectable, all channels
            gap_advertisements_set_data(sizeof adv_data, (uint8_t *)adv_data);
            gap_scan_response_set_data(sizeof scan_data, (uint8_t *)scan_data);
            gap_advertisements_enable(1);
            printf("setup: advertising as BellAI Recorder for %d s\n", PROVISION_WINDOW_SECONDS);
        }
        break;
    case HCI_EVENT_LE_META:
        if (hci_event_le_meta_get_subevent_code(packet) == HCI_SUBEVENT_LE_CONNECTION_COMPLETE) {
            connected = true;
            printf("setup: phone connected, interval %u x1.25 ms\n", hci_subevent_le_connection_complete_get_conn_interval(packet));
        } else if (hci_event_le_meta_get_subevent_code(packet) == HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V1) {
            connected = true;
            printf("setup: phone connected (enhanced)\n");
        }
        break;
    case ATT_EVENT_MTU_EXCHANGE_COMPLETE:
        printf("setup: ATT MTU %u\n", att_event_mtu_exchange_complete_get_MTU(packet));
        break;
    case HCI_EVENT_DISCONNECTION_COMPLETE:
        printf("setup: phone disconnected, reason 0x%02x\n", hci_event_disconnection_complete_get_reason(packet));
        connected = false;
        gap_advertisements_enable(1);                  // the app may need a second try
        break;
    }
}

void provision_begin(void) {
    if (cyw43_arch_init_with_country(CYW43_COUNTRY_USA)) { printf("setup: radio init failed, Bluetooth setup unavailable\n"); return; }
    l2cap_init();
    sm_init();
    att_server_init(profile_data, NULL, on_write);
    att_server_register_packet_handler(on_hci);        // ATT events (MTU) come here, not through hci_add_event_handler
    hci_callback.callback = &on_hci;
    hci_add_event_handler(&hci_callback);
    deadline_ms = now_ms() + PROVISION_WINDOW_SECONDS * 1000u;
    active = true;
    hci_power_control(HCI_POWER_ON);
}

bool provision_active(void) { return active; }

static void end_window(void) {
    cyw43_arch_deinit();                               // stops Bluetooth with it; radio fully off until the first upload
    active = connected = false;
    printf("setup: Bluetooth off\n");
}

void provision_step(bool sd_ready) {
    if (!active) return;
    uint32_t t = now_ms();
    static uint32_t last_beat;
    if (t - last_beat >= 10000) {
        last_beat = t;
        printf("setup: window open, %ld s left, phone %s\n", (long)((int32_t)(deadline_ms - t) / 1000), connected ? "connected" : "not connected");
    }
    if (staged && sd_ready) {
        bool ok = wifi_cfg_save(staged_ssid, staged_pass);
        printf(ok ? "setup: saved Wi-Fi \"%s\" to /wifi.txt\n" : "setup: could not save \"%s\" to /wifi.txt\n", staged_ssid);
        staged = false;
        memset(staged_pass, 0, sizeof staged_pass);
        if (ok) { sync_request(SAVED_LINGER_MS); linger_until_ms = t + SAVED_LINGER_MS; }
    }
    bool saved_and_done = linger_until_ms && (int32_t)(t - linger_until_ms) >= 0;
    bool expired = (int32_t)(t - deadline_ms) >= 0 && (!connected || (int32_t)(t - deadline_ms) >= (int32_t)CONNECTED_GRACE_MS);
    if (saved_and_done || expired) end_window();
}
