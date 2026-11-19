#pragma once
// Minimal lwIP config for the recorder: IPv4, DHCP, raw TCP client. No sockets, no DNS.
#define NO_SYS                      1
#define LWIP_SOCKET                 0
#define LWIP_NETCONN                0
#define MEM_LIBC_MALLOC             0
#define MEM_ALIGNMENT               4
#define MEM_SIZE                    32768   // tcp_write(COPY) allocates the send queue here: must hold TCP_SND_BUF plus pbuf headers
#define MEMP_NUM_TCP_SEG            64      // must be >= TCP_SND_QUEUELEN
#define MEMP_NUM_TCP_PCB            24      // the server scan opens 16 connections at once
#define ARP_TABLE_SIZE              32      // ...each needing an ARP entry
#define ARP_QUEUEING                1       // hold the SYN until ARP resolves instead of waiting for a 3 s retransmit
#define MEMP_NUM_ARP_QUEUE          32
#define PBUF_POOL_SIZE              24
#define LWIP_ARP                    1
#define LWIP_ETHERNET               1
#define LWIP_ICMP                   1
#define LWIP_RAW                    1
#define LWIP_IPV4                   1
#define LWIP_TCP                    1
#define LWIP_UDP                    1
#define LWIP_DHCP                   1
#define LWIP_DNS                    0
#define TCP_MSS                     1460
#define TCP_WND                     (8 * TCP_MSS)
#define TCP_SND_BUF                 (16 * TCP_MSS)
#define TCP_SND_QUEUELEN            ((4 * (TCP_SND_BUF) + (TCP_MSS - 1)) / (TCP_MSS))
#define LWIP_NETIF_STATUS_CALLBACK  1
#define LWIP_NETIF_LINK_CALLBACK    1
#define LWIP_NETIF_HOSTNAME         1
#define LWIP_NETIF_TX_SINGLE_PBUF   1
#define LWIP_CHKSUM_ALGORITHM       3
#define LWIP_TCP_KEEPALIVE          1
#define DHCP_DOES_ARP_CHECK         0
#define LWIP_DHCP_DOES_ACD_CHECK    0
#define MEM_STATS                   0
#define SYS_STATS                   0
#define MEMP_STATS                  0
#define LINK_STATS                  0
#define LWIP_STATS                  0
