#ifndef MIXTAR_SIGNIFY_COMPAT_H
#define MIXTAR_SIGNIFY_COMPAT_H

#include <endian.h>
#include <stddef.h>

#ifndef __dead
#define __dead __attribute__((__noreturn__))
#endif

#ifndef BYTE_ORDER
#define BYTE_ORDER __BYTE_ORDER
#endif
#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN __BIG_ENDIAN
#endif

#define DEF_WEAK(symbol)

int pledge(const char *promises, const char *execpromises);
const char *getprogname(void);
size_t strlcpy(char *destination, const char *source, size_t size);
int timingsafe_bcmp(const void *left, const void *right, size_t length);
int b64_pton(const char *source, unsigned char *target, size_t size);
int b64_ntop(const unsigned char *source, size_t source_length,
    char *target, size_t target_size);

#endif
