/* Mixtar Bridge UUID libc shim for FreeBSD/OpenBSD userland sources. */
#ifndef MIXTAR_BRIDGE_UUID_H
#define MIXTAR_BRIDGE_UUID_H

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uuid.h>

#ifndef uuid_s_ok
#define uuid_s_ok 0
#endif
#ifndef uuid_s_bad_version
#define uuid_s_bad_version 1
#endif
#ifndef uuid_s_invalid_string_uuid
#define uuid_s_invalid_string_uuid 2
#endif
#ifndef uuid_s_no_memory
#define uuid_s_no_memory 3
#endif

#ifndef UUID_BUF_LEN
#define UUID_BUF_LEN _UUID_BUF_LEN
#endif
#ifndef UUID_STR_LEN
#define UUID_STR_LEN 36
#endif

static inline void
uuid_create_nil(uuid_t *u, uint32_t *status)
{
	if (u != NULL)
		memset(u, 0, sizeof(*u));
	if (status != NULL)
		*status = uuid_s_ok;
}

static inline void
uuid_to_string(const uuid_t *u, char **s, uint32_t *status)
{
	uuid_t nil;

	if (status != NULL)
		*status = uuid_s_ok;
	if (s == NULL)
		return;
	if (u == NULL) {
		uuid_create_nil(&nil, NULL);
		u = &nil;
	}
	if (asprintf(s, "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
	    u->time_low, u->time_mid, u->time_hi_and_version,
	    u->clock_seq_hi_and_reserved, u->clock_seq_low, u->node[0],
	    u->node[1], u->node[2], u->node[3], u->node[4], u->node[5]) == -1) {
		if (status != NULL)
			*status = uuid_s_no_memory;
		*s = NULL;
	}
}

static inline int
uuidgen(uuid_t *store, int count)
{
	uuid_t *item;

	if (store == NULL || count < 1) {
		errno = EINVAL;
		return -1;
	}
	arc4random_buf(store, sizeof(*store) * (size_t)count);
	item = store;
	for (int i = 0; i < count; i++) {
		item->clock_seq_hi_and_reserved &= ~(uint8_t)(3U << 6);
		item->clock_seq_hi_and_reserved |= (uint8_t)(2U << 6);
		item->time_hi_and_version &= ~(uint16_t)(15U << 12);
		item->time_hi_and_version |= (uint16_t)(4U << 12);
		item++;
	}
	return 0;
}

static inline void
uuid_create(uuid_t *u, uint32_t *status)
{
	if (u == NULL) {
		if (status != NULL)
			*status = uuid_s_no_memory;
		return;
	}
	if (uuidgen(u, 1) == 0) {
		if (status != NULL)
			*status = uuid_s_ok;
		return;
	}
	uuid_create_nil(u, NULL);
	if (status != NULL)
		*status = uuid_s_no_memory;
}

static inline int
uuid_is_nil(const uuid_t *u, uint32_t *status)
{
	static const uuid_t nil;

	if (status != NULL)
		*status = uuid_s_ok;
	if (u == NULL)
		return 1;
	return memcmp(u, &nil, sizeof(*u)) == 0;
}

static inline int
uuid_compare(const uuid_t *a, const uuid_t *b, uint32_t *status)
{
	if (status != NULL)
		*status = uuid_s_ok;
	if (a == NULL && b == NULL)
		return 0;
	if (a == NULL)
		return -1;
	if (b == NULL)
		return 1;
	return memcmp(a, b, sizeof(*a));
}

static inline void
uuid_from_string(const char *s, uuid_t *u, uint32_t *status)
{
	unsigned int n[11];

	if (u == NULL || s == NULL) {
		if (status != NULL)
			*status = uuid_s_invalid_string_uuid;
		return;
	}
	if (sscanf(s, "%8x-%4x-%4x-%2x%2x-%2x%2x%2x%2x%2x%2x",
	    &n[0], &n[1], &n[2], &n[3], &n[4], &n[5], &n[6], &n[7],
	    &n[8], &n[9], &n[10]) != 11) {
		uuid_create_nil(u, NULL);
		if (status != NULL)
			*status = uuid_s_invalid_string_uuid;
		return;
	}
	u->time_low = (uint32_t)n[0];
	u->time_mid = (uint16_t)n[1];
	u->time_hi_and_version = (uint16_t)n[2];
	u->clock_seq_hi_and_reserved = (uint8_t)n[3];
	u->clock_seq_low = (uint8_t)n[4];
	for (int i = 0; i < 6; i++)
		u->node[i] = (uint8_t)n[5 + i];
	if (status != NULL)
		*status = uuid_s_ok;
}

static inline void
uuid_dec_be(const void *buf, uuid_t *u)
{
	const uint8_t *b = (const uint8_t *)buf;

	if (buf == NULL || u == NULL)
		return;
	u->time_low = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
	    ((uint32_t)b[2] << 8) | (uint32_t)b[3];
	u->time_mid = (uint16_t)(((uint16_t)b[4] << 8) | b[5]);
	u->time_hi_and_version = (uint16_t)(((uint16_t)b[6] << 8) | b[7]);
	u->clock_seq_hi_and_reserved = b[8];
	u->clock_seq_low = b[9];
	memcpy(u->node, b + 10, sizeof(u->node));
}

static inline void
uuid_enc_be(void *buf, const uuid_t *u)
{
	uint8_t *b = (uint8_t *)buf;

	if (buf == NULL || u == NULL)
		return;
	b[0] = (uint8_t)(u->time_low >> 24);
	b[1] = (uint8_t)(u->time_low >> 16);
	b[2] = (uint8_t)(u->time_low >> 8);
	b[3] = (uint8_t)u->time_low;
	b[4] = (uint8_t)(u->time_mid >> 8);
	b[5] = (uint8_t)u->time_mid;
	b[6] = (uint8_t)(u->time_hi_and_version >> 8);
	b[7] = (uint8_t)u->time_hi_and_version;
	b[8] = u->clock_seq_hi_and_reserved;
	b[9] = u->clock_seq_low;
	memcpy(b + 10, u->node, sizeof(u->node));
}

static inline void
uuid_dec_le(const void *buf, uuid_t *u)
{
	const uint8_t *b = (const uint8_t *)buf;

	if (buf == NULL || u == NULL)
		return;
	u->time_low = ((uint32_t)b[3] << 24) | ((uint32_t)b[2] << 16) |
	    ((uint32_t)b[1] << 8) | (uint32_t)b[0];
	u->time_mid = (uint16_t)(((uint16_t)b[5] << 8) | b[4]);
	u->time_hi_and_version = (uint16_t)(((uint16_t)b[7] << 8) | b[6]);
	u->clock_seq_hi_and_reserved = b[8];
	u->clock_seq_low = b[9];
	memcpy(u->node, b + 10, sizeof(u->node));
}

static inline void
uuid_enc_le(void *buf, const uuid_t *u)
{
	uint8_t *b = (uint8_t *)buf;

	if (buf == NULL || u == NULL)
		return;
	b[0] = (uint8_t)u->time_low;
	b[1] = (uint8_t)(u->time_low >> 8);
	b[2] = (uint8_t)(u->time_low >> 16);
	b[3] = (uint8_t)(u->time_low >> 24);
	b[4] = (uint8_t)u->time_mid;
	b[5] = (uint8_t)(u->time_mid >> 8);
	b[6] = (uint8_t)u->time_hi_and_version;
	b[7] = (uint8_t)(u->time_hi_and_version >> 8);
	b[8] = u->clock_seq_hi_and_reserved;
	b[9] = u->clock_seq_low;
	memcpy(b + 10, u->node, sizeof(u->node));
}

#endif /* MIXTAR_BRIDGE_UUID_H */
