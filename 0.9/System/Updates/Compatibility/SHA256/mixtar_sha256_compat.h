#ifndef MIXTAR_SHA256_COMPAT_H
#define MIXTAR_SHA256_COMPAT_H

#include <endian.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifndef BYTE_ORDER
#define BYTE_ORDER __BYTE_ORDER
#endif
#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN __BIG_ENDIAN
#endif

#ifndef __bounded__
#define __bounded__(kind, position, length)
#endif

#ifndef __BEGIN_DECLS
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#endif

/* OpenBSD emits weak aliases for libc. Mixtar links one private copy. */
#ifndef DEF_WEAK
#define DEF_WEAK(symbol) typedef int mixtar_def_weak_##symbol
#endif

#ifndef MAKE_CLONE
#define MAKE_CLONE(symbol, target) \
    extern __typeof__(target) symbol __attribute__((alias(#target)))
#endif

#endif
