/* Mixtar Bridge UUID ABI shim for FreeBSD/OpenBSD userland sources. */
#ifndef MIXTAR_BRIDGE_SYS_UUID_H
#define MIXTAR_BRIDGE_SYS_UUID_H

#include <stdint.h>

#define _UUID_BUF_LEN 37
#define UUIDGEN_BATCH_MAX 1024

struct uuid {
	uint32_t time_low;
	uint16_t time_mid;
	uint16_t time_hi_and_version;
	uint8_t clock_seq_hi_and_reserved;
	uint8_t clock_seq_low;
	uint8_t node[6];
};

typedef struct uuid uuid_t;

#endif /* MIXTAR_BRIDGE_SYS_UUID_H */
