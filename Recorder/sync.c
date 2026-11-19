// Hourly upload: bring Wi-Fi up, POST every finished WAV to the receiver, delete each file only after
// the receiver echoes back the exact byte count and CRC32, then shut the radio down again.
// Written as a non-blocking state machine so the main loop can keep writing audio to the SD card.
//
// Protocol (same as receiver.py):
//   POST /upload  X-Auth, X-Filename, Content-Length   ->   200, body "OK <bytes> <crc32 hex>"
#include "sync.h"
#include "config.h"
#include "wifi_cfg.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pico/stdlib.h"
#include "pico/cyw43_arch.h"
#include "lwip/tcp.h"
#include "lwip/ip4_addr.h"
#include "lwip/netif.h"
#include "ff.h"

typedef enum { S_IDLE, S_WIFI_WAIT, S_SCAN, S_FILE_OPEN, S_CONNECTING, S_SENDING, S_WAIT_RESP } state_t;

static state_t st = S_IDLE;
static bool pending;
static uint32_t not_before_ms;
static uint32_t t_state, t_progress;

static char names[MAX_BACKLOG_FILES][28];
static int nfiles, fidx;

static FIL fil;
static bool fil_open;
static char path[48];
static uint32_t total, sent, crc;
static uint8_t chunk[SEND_CHUNK];

static struct tcp_pcb *pcb;
static volatile bool connected, failed;
static volatile bool peer_closed;
static char resp[256];
static volatile size_t resp_len;

static ip4_addr_t server_ip;              // receiver found by the scan, remembered between runs
static bool server_known, scanned_this_run;
static char server_txt[16];               // server_ip as text
static volatile err_t last_err;           // last lwIP error from a callback, for diagnostics
static int last_ls;                       // last Wi-Fi link status printed

static char wifi_ssid[WIFI_SSID_MAX + 1], wifi_pass[WIFI_PASS_MAX + 1];   // /wifi.txt or config.h, read at the start of each run

static uint32_t crc_table[256];

static const char *link_name(int ls) {
    switch (ls) {
    case CYW43_LINK_DOWN:    return "DOWN (not joined yet)";
    case CYW43_LINK_JOIN:    return "JOINED (waiting for DHCP)";
    case CYW43_LINK_NOIP:    return "JOINED, NO IP (DHCP not answered)";
    case CYW43_LINK_UP:      return "UP";
    case CYW43_LINK_FAIL:    return "FAIL (join failed)";
    case CYW43_LINK_NONET:   return "NONET (SSID not found: wrong name, or not 2.4 GHz)";
    case CYW43_LINK_BADAUTH: return "BADAUTH (wrong password or security type)";
    default:                 return "?";
    }
}

static const char *lwip_err_name(int e) {
    switch (e) {
    case 0:   return "OK";
    case -1:  return "MEM (out of memory)";
    case -3:  return "TIMEOUT";
    case -4:  return "RTE (no route to server)";
    case -13: return "ABRT (connection aborted)";
    case -14: return "RST (connection refused or reset: nothing listening on that port?)";
    case -15: return "CLSD (connection closed)";
    default:  return "other lwIP error";
    }
}

static uint32_t now_ms(void) { return to_ms_since_boot(get_absolute_time()); }

// ---------------------------------------------------------------- CRC32 (zlib compatible)
static void crc_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_table[i] = c;
    }
}
static uint32_t crc32_update(uint32_t c, const uint8_t *p, size_t n) {
    c = ~c;
    while (n--) c = crc_table[(c ^ *p++) & 0xFF] ^ (c >> 8);
    return ~c;
}

// ---------------------------------------------------------------- lwIP callbacks (run with the lwIP lock held)
static err_t on_connected(void *arg, struct tcp_pcb *tpcb, err_t err) {
    (void)arg; (void)tpcb;
    last_err = err;
    if (err == ERR_OK) connected = true; else failed = true;
    return ERR_OK;
}
static err_t on_recv(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err) {
    (void)arg; (void)err;
    if (!p) { peer_closed = true; return ERR_OK; }
    size_t room = sizeof(resp) - 1 - resp_len;
    size_t n = p->tot_len < room ? p->tot_len : room;
    if (n) pbuf_copy_partial(p, resp + resp_len, n, 0);
    resp_len += n;
    resp[resp_len] = 0;
    tcp_recved(tpcb, p->tot_len);
    pbuf_free(p);
    return ERR_OK;
}
static void on_err(void *arg, err_t err) {   // lwIP has already freed the pcb
    (void)arg;
    last_err = err;
    pcb = NULL;
    failed = true;
}

static void tcp_cleanup(void) {
    cyw43_arch_lwip_begin();
    if (pcb) {
        tcp_arg(pcb, NULL); tcp_recv(pcb, NULL); tcp_err(pcb, NULL);
        if (tcp_close(pcb) != ERR_OK) tcp_abort(pcb);
        pcb = NULL;
    }
    cyw43_arch_lwip_end();
}

// ---------------------------------------------------------------- helpers
static void enter(state_t s) { st = s; t_state = t_progress = now_ms(); }

static void finish(bool ok);

// Logs the reason, then fails the sync. Every failure path goes through here so the cause is never silent.
static void fail(const char *why) {
    printf("sync: %s\n", why);
    finish(false);
}

static void finish(bool ok) {
    tcp_cleanup();
    if (fil_open) { f_close(&fil); fil_open = false; }
    cyw43_arch_deinit();                       // radio fully off until the next run
    st = S_IDLE;
    if (!ok) { pending = true; not_before_ms = now_ms() + RETRY_DELAY_MS; }
    printf("sync %s\n", ok ? "done" : "failed, will retry");
}

static int cmp_names(const void *a, const void *b) { return strcmp((const char *)a, (const char *)b); }

static void scan_files(const char *current) {
    nfiles = 0; fidx = 0;
    DIR dir; FILINFO fno;
    if (f_opendir(&dir, "/rec") != FR_OK) return;
    while (nfiles < MAX_BACKLOG_FILES && f_readdir(&dir, &fno) == FR_OK && fno.fname[0]) {
        if (fno.fattrib & AM_DIR) continue;
        size_t l = strlen(fno.fname);
        if (l < 5 || l >= sizeof(names[0]) || strcmp(fno.fname + l - 4, ".wav") != 0) continue;
        if (current && strcmp(fno.fname, current) == 0) continue;
        strcpy(names[nfiles++], fno.fname);
    }
    f_closedir(&dir);
    qsort(names, nfiles, sizeof(names[0]), cmp_names);     // oldest first (zero-padded sequence numbers)
}

static bool response_complete(void) {
    const char *body = strstr(resp, "\r\n\r\n");
    if (!body) return false;
    body += 4;
    const char *cl = strstr(resp, "Content-Length:");
    if (!cl) return false;                                  // fall back to connection close
    size_t want = (size_t)atoi(cl + 15);
    return strlen(body) >= want && want > 0;
}

static bool response_ok(void) {
    if (!strstr(resp, " 200")) return false;
    const char *body = strstr(resp, "\r\n\r\n");
    if (!body) return false;
    unsigned long len = 0, rc = 0;
    if (sscanf(body + 4, "OK %lu %lx", &len, &rc) != 2) return false;
    return len == total && (uint32_t)rc == crc;
}

static bool send_header(void) {
    char hdr[300];
    int n = snprintf(hdr, sizeof hdr,
        "POST /upload HTTP/1.1\r\nHost: %s\r\nX-Auth: %s\r\nX-Filename: %s\r\n"
        "Content-Type: application/octet-stream\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        server_txt, AUTH_TOKEN, names[fidx], (unsigned long)total);
    cyw43_arch_lwip_begin();
    err_t e = pcb ? tcp_write(pcb, hdr, (u16_t)n, TCP_WRITE_FLAG_COPY) : ERR_CLSD;
    if (e == ERR_OK) tcp_output(pcb);
    cyw43_arch_lwip_end();
    return e == ERR_OK;
}

// Reads up to two chunks from the SD card into the TCP send buffer. Returns false on a fatal error.
static bool send_pump(void) {
    for (int n = 0; n < 2 && sent < total; n++) {
        uint32_t want = total - sent;
        if (want > SEND_CHUNK) want = SEND_CHUNK;

        cyw43_arch_lwip_begin();
        bool alive = pcb && !failed;
        bool room = alive && tcp_sndbuf(pcb) >= want && (tcp_sndqueuelen(pcb) + 8) < TCP_SND_QUEUELEN;
        cyw43_arch_lwip_end();
        if (!alive) { printf("sync: send: connection already gone (pcb %s, error flag %d)\n", pcb ? "set" : "NULL", (int)failed); return false; }
        if (!room) return true;                              // wait for ACKs

        UINT br;
        FRESULT fr = f_read(&fil, chunk, want, &br);
        if (fr != FR_OK || br != want) { printf("sync: send: f_read FRESULT %d, got %u of %lu bytes at offset %lu\n",
                                                (int)fr, (unsigned)br, (unsigned long)want, (unsigned long)sent); return false; }
        crc = crc32_update(crc, chunk, br);

        cyw43_arch_lwip_begin();
        err_t e = pcb ? tcp_write(pcb, chunk, (u16_t)br, TCP_WRITE_FLAG_COPY) : ERR_CLSD;
        if (e == ERR_OK) tcp_output(pcb);
        cyw43_arch_lwip_end();
        if (e != ERR_OK) { printf("sync: send: tcp_write error %d, %s\n", (int)e, lwip_err_name(e)); return false; }
        sent += br;
        t_progress = now_ms();
    }
    return true;
}

// ---------------------------------------------------------------- server discovery
// No fixed server address: after joining Wi-Fi, probe every host of our subnet for TCP SERVER_PORT, 16 at a
// time, and ask each one that accepts "GET /ping". Only a host answering with PING_MARKER counts, so a router
// or any other service that happens to listen on that port is ignored. The result is remembered until a connect
// to it fails, which triggers one rescan.
#define SCAN_SLOTS   16
#define SCAN_SLOT_MS 2000
#define PING_MARKER  "recorder-receiver"

typedef struct { struct tcp_pcb *pcb; uint32_t ip; uint32_t t0; size_t len; char buf[320]; } slot_t;  // ip: network order
static slot_t slots[SCAN_SLOTS];
static uint32_t scan_next, scan_last, scan_self;        // host-order addresses
static volatile bool scan_found;
static uint32_t scan_found_ip;                          // network order

static err_t scan_connected(void *arg, struct tcp_pcb *p, err_t err) {
    if (!arg || err != ERR_OK) return ERR_OK;
    static const char req[] = "GET /ping HTTP/1.0\r\n\r\n";
    if (tcp_write(p, req, sizeof req - 1, 0) == ERR_OK) tcp_output(p);
    return ERR_OK;
}
static err_t scan_recv(void *arg, struct tcp_pcb *p, struct pbuf *pb, err_t err) {
    (void)err;
    slot_t *s = arg;
    if (!pb) return ERR_OK;                              // peer closed without the marker: the slot times out
    if (s) {
        size_t room = sizeof s->buf - 1 - s->len;
        size_t n = pb->tot_len < room ? pb->tot_len : room;
        if (n) pbuf_copy_partial(pb, s->buf + s->len, n, 0);
        s->len += n;
        s->buf[s->len] = 0;
        if (strstr(s->buf, PING_MARKER)) { scan_found_ip = s->ip; scan_found = true; }
    }
    tcp_recved(p, pb->tot_len);
    pbuf_free(pb);
    return ERR_OK;
}
static void scan_err(void *arg, err_t err) {             // refused/reset: lwIP has already freed the pcb
    (void)err;
    slot_t *s = arg;
    if (s) s->pcb = NULL;
}

static void slot_free(slot_t *s) {                       // lwIP lock must be held
    if (!s->pcb) return;
    tcp_arg(s->pcb, NULL); tcp_recv(s->pcb, NULL); tcp_err(s->pcb, NULL);
    tcp_abort(s->pcb);                                   // no TIME_WAIT left behind
    s->pcb = NULL;
}

static void start_scan(void) {
    cyw43_arch_lwip_begin();
    uint32_t me = lwip_ntohl(ip4_addr_get_u32(netif_ip4_addr(netif_default)));
    uint32_t mask = lwip_ntohl(ip4_addr_get_u32(netif_ip4_netmask(netif_default)));
    cyw43_arch_lwip_end();
    if (mask < 0xFFFFFF00u) mask = 0xFFFFFF00u;          // never more than the /24 we are in
    uint32_t net = me & mask;
    scan_self = me; scan_next = net + 1; scan_last = (net | ~mask) - 1;
    scan_found = false; scanned_this_run = true;
    memset(slots, 0, sizeof slots);
    printf("sync: scanning %u.%u.%u.%u-%u for the receiver on port %d\n", (unsigned)(net >> 24) & 255, (unsigned)(net >> 16) & 255,
           (unsigned)(net >> 8) & 255, (unsigned)(scan_next & 255), (unsigned)(scan_last & 255), SERVER_PORT);
    enter(S_SCAN);
}

static void scan_step(void) {
    uint32_t t = now_ms();
    bool idle = true;
    cyw43_arch_lwip_begin();
    for (int i = 0; i < SCAN_SLOTS && !scan_found; i++) {
        slot_t *s = &slots[i];
        if (s->pcb && t - s->t0 > SCAN_SLOT_MS) slot_free(s);
        while (!s->pcb && scan_next <= scan_last) {
            uint32_t host = scan_next++;
            if (host == scan_self) continue;
            ip_addr_t dst;
            ip4_addr_set_u32(ip_2_ip4(&dst), lwip_htonl(host));
            IP_SET_TYPE_VAL(dst, IPADDR_TYPE_V4);
            struct tcp_pcb *p = tcp_new_ip_type(IPADDR_TYPE_V4);
            if (!p) { scan_next--; break; }                // out of pcbs: retry on the next step
            s->pcb = p; s->ip = ip4_addr_get_u32(ip_2_ip4(&dst)); s->t0 = t; s->len = 0; s->buf[0] = 0;
            tcp_arg(p, s); tcp_recv(p, scan_recv); tcp_err(p, scan_err);
            if (tcp_connect(p, &dst, SERVER_PORT, scan_connected) != ERR_OK) slot_free(s);
        }
        if (s->pcb) idle = false;
    }
    bool found = scan_found;
    if (found) for (int i = 0; i < SCAN_SLOTS; i++) slot_free(&slots[i]);
    cyw43_arch_lwip_end();

    if (found) {
        ip4_addr_set_u32(&server_ip, scan_found_ip);
        server_known = true;
        ip4addr_ntoa_r(&server_ip, server_txt, sizeof server_txt);
        printf("sync: found the receiver at %s:%d\n", server_txt, SERVER_PORT);
        enter(S_FILE_OPEN);
    } else if (idle && scan_next > scan_last) {
        fail("receiver not found: nothing on this subnet answered on the port as the recorder receiver "
             "(is receiver.py running on a machine on this Wi-Fi?)");
    }
}

// A connect failure to a remembered server means it moved or is down: scan once to find it again.
static bool rescan_after_connect_failure(void) {
    if (!server_known || scanned_this_run) return false;
    printf("sync: server %s:%d not answering, rescanning the network\n", server_txt, SERVER_PORT);
    server_known = false;
    tcp_cleanup();
    if (fil_open) { f_close(&fil); fil_open = false; }
    start_scan();
    return true;
}

// ---------------------------------------------------------------- public API
void sync_init(void) { crc_init(); }

void sync_request(uint32_t delay_ms) {
    pending = true;
    uint32_t t = now_ms() + delay_ms;
    if (st == S_IDLE) not_before_ms = t;       // a running sync will pick up newly finished files via pending
}

bool sync_busy(void) { return st != S_IDLE; }

void sync_step(const char *current) {
    switch (st) {
    case S_IDLE:
        if (!pending || (int32_t)(now_ms() - not_before_ms) < 0) break;
        pending = false;
        scan_files(current);
        if (nfiles == 0) break;
        printf("sync: %d file(s) to upload, starting Wi-Fi\n", nfiles);
        if (cyw43_arch_init_with_country(CYW43_COUNTRY_USA)) {
            printf("sync: Wi-Fi chip init failed (will retry)\n");
            pending = true; not_before_ms = now_ms() + RETRY_DELAY_MS; break;
        }
        cyw43_arch_enable_sta_mode();
        cyw43_wifi_pm(&cyw43_state, CYW43_NONE_PM);          // full speed for the burst
        wifi_cfg_load(wifi_ssid, wifi_pass);
        printf("sync: joining \"%s\"\n", wifi_ssid);
        { int r = cyw43_arch_wifi_connect_async(wifi_ssid, wifi_pass, wifi_pass[0] ? CYW43_AUTH_WPA2_AES_PSK : CYW43_AUTH_OPEN);
          if (r) { printf("sync: join request rejected, code %d\n", r); fail("could not start Wi-Fi join"); break; } }
        last_ls = -99;
        enter(S_WIFI_WAIT);
        break;

    case S_WIFI_WAIT: {
        int ls = cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA);
        if (ls != last_ls) { last_ls = ls; printf("sync: Wi-Fi link %s\n", link_name(ls)); }
        if (ls == CYW43_LINK_UP) {
            cyw43_arch_lwip_begin();
            printf("sync: Wi-Fi up, my IP %s\n", ip4addr_ntoa(netif_ip4_addr(netif_default)));
            cyw43_arch_lwip_end();
            scanned_this_run = false;
            if (server_known) enter(S_FILE_OPEN); else start_scan();
        }
        else if (ls < 0) fail("Wi-Fi join failed (see link status above)");
        else if (now_ms() - t_state > 30000) fail("Wi-Fi join timed out after 30 s");
        break; }

    case S_SCAN:
        scan_step();
        break;

    case S_FILE_OPEN: {
        if (fidx >= nfiles) { finish(true); break; }
        snprintf(path, sizeof path, "/rec/%s", names[fidx]);
        { FRESULT fr = f_open(&fil, path, FA_READ);
          if (fr != FR_OK) { printf("sync: cannot open %s, FRESULT %d\n", path, (int)fr); fail("SD read error"); break; } }
        fil_open = true;
        total = f_size(&fil); sent = 0; crc = 0;
        if (total == 0) { f_close(&fil); fil_open = false; f_unlink(path); fidx++; break; }

        connected = failed = peer_closed = false; resp_len = 0; resp[0] = 0;
        ip_addr_t ip;
        ip4_addr_copy(*ip_2_ip4(&ip), server_ip);
        IP_SET_TYPE_VAL(ip, IPADDR_TYPE_V4);
        cyw43_arch_lwip_begin();
        pcb = tcp_new_ip_type(IPADDR_TYPE_V4);
        err_t e = ERR_MEM;
        if (pcb) {
            tcp_arg(pcb, NULL); tcp_recv(pcb, on_recv); tcp_err(pcb, on_err);
            e = tcp_connect(pcb, &ip, SERVER_PORT, on_connected);
        }
        cyw43_arch_lwip_end();
        if (e != ERR_OK) { printf("sync: tcp_connect error %d, %s\n", (int)e, lwip_err_name(e)); fail("TCP connect could not start"); break; }
        printf("sync: connecting to %s:%d to send %s (%lu bytes)\n", server_txt, SERVER_PORT, names[fidx], (unsigned long)total);
        enter(S_CONNECTING);
        break; }

    case S_CONNECTING:
        if (failed) {
            printf("sync: connect error %d, %s\n", (int)last_err, lwip_err_name(last_err));
            if (!rescan_after_connect_failure()) fail("TCP connect failed");
            break;
        }
        if (now_ms() - t_state > 10000) {
            printf("sync: TCP connect timed out after 10 s\n");
            if (!rescan_after_connect_failure())
                fail("no reply from the server (receiver not running, Mac not on this network, router client isolation, or firewall)");
            break;
        }
        if (connected) {
            printf("sync: connected, sending\n");
            if (!send_header()) { fail("could not send HTTP header"); break; }
            enter(S_SENDING);
        }
        break;

    case S_SENDING:
        if (failed) { printf("sync: send error %d, %s, after %lu of %lu bytes\n", (int)last_err, lwip_err_name(last_err),
                             (unsigned long)sent, (unsigned long)total); fail("connection lost while sending"); break; }
        if (!send_pump()) { printf("sync: stopped at %lu of %lu bytes\n", (unsigned long)sent, (unsigned long)total);
                            fail("SD read error or send buffer error while sending"); break; }
        if (now_ms() - t_progress > 20000) { printf("sync: stalled at %lu of %lu bytes\n", (unsigned long)sent, (unsigned long)total);
                                             fail("no progress for 20 s while sending"); break; }
        if (sent >= total) enter(S_WAIT_RESP);
        break;

    case S_WAIT_RESP:
        if (failed && !peer_closed && resp_len == 0) { printf("sync: error %d, %s, waiting for reply\n", (int)last_err, lwip_err_name(last_err));
                                                       fail("connection lost before the server replied"); break; }
        if (peer_closed || response_complete() || now_ms() - t_state > 15000) {
            bool ok = response_ok();
            if (!ok) printf("sync: server reply was: [%s]\nsync: expected \"OK %lu %lx\" with HTTP 200\n",
                            resp, (unsigned long)total, (unsigned long)crc);
            tcp_cleanup();
            f_close(&fil); fil_open = false;
            if (!ok) { fail("server reply missing or did not match (403 = wrong token, 400 = bad name, empty = no reply)"); break; }
            f_unlink(path);                                 // verified: safe to delete
            printf("uploaded and deleted %s\n", path);
            fidx++;
            enter(S_FILE_OPEN);
        }
        break;
    }
}
