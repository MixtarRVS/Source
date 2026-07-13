#ifndef MIXTAR_OPENBSD_SHA2_H
#define MIXTAR_OPENBSD_SHA2_H

#include <sys/types.h>

#include <stddef.h>

#define SHA256_BLOCK_LENGTH 64
#define SHA256_DIGEST_LENGTH 32
#define SHA256_DIGEST_STRING_LENGTH 65
#define SHA512_BLOCK_LENGTH 128
#define SHA512_DIGEST_LENGTH 64
#define SHA512_DIGEST_STRING_LENGTH 129

typedef struct _SHA2_CTX {
	union {
		u_int32_t st32[8];
		u_int64_t st64[8];
	} state;
	u_int64_t bitcount[2];
	u_int8_t buffer[SHA512_BLOCK_LENGTH];
} SHA2_CTX;

void SHA256Init(SHA2_CTX *);
void SHA256Transform(u_int32_t state[8],
    const u_int8_t data[SHA256_BLOCK_LENGTH]);
void SHA256Update(SHA2_CTX *, const u_int8_t *, size_t);
void SHA256Pad(SHA2_CTX *);
void SHA256Final(u_int8_t digest[SHA256_DIGEST_LENGTH], SHA2_CTX *);

void SHA512Init(SHA2_CTX *);
void SHA512Transform(u_int64_t state[8],
    const u_int8_t data[SHA512_BLOCK_LENGTH]);
void SHA512Update(SHA2_CTX *, const u_int8_t *, size_t);
void SHA512Pad(SHA2_CTX *);
void SHA512Final(u_int8_t digest[SHA512_DIGEST_LENGTH], SHA2_CTX *);

#endif
