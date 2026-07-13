#ifndef MIXTAR_BRIDGE_SIPHASH_H
#define MIXTAR_BRIDGE_SIPHASH_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define SIPHASH_DIGEST_LENGTH 8

typedef struct {
	uint64_t k0;
	uint64_t k1;
} SIPHASH_KEY;

typedef struct {
	uint64_t state;
} SIPHASH_CTX;

static inline void
SipHash24_Init(SIPHASH_CTX *ctx, const SIPHASH_KEY *key)
{
	ctx->state = key != NULL ? (key->k0 ^ key->k1) : 0;
}

static inline void
SipHash24_Update(SIPHASH_CTX *ctx, const void *data, size_t len)
{
	const unsigned char *p = (const unsigned char *)data;
	size_t i;

	for (i = 0; i < len; i++)
		ctx->state = (ctx->state * 1315423911ULL) ^ p[i];
}

static inline void
SipHash24_Final(void *out, SIPHASH_CTX *ctx)
{
	uint64_t value = ctx->state;
	memcpy(out, &value, SIPHASH_DIGEST_LENGTH);
}

#endif /* MIXTAR_BRIDGE_SIPHASH_H */
