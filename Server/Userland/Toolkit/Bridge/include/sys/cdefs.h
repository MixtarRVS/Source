#ifndef MIXTAR_BRIDGE_SYS_CDEFS_H
#define MIXTAR_BRIDGE_SYS_CDEFS_H

/* FreeBSD source includes <sys/cdefs.h>; musl intentionally has no such file. */
#ifndef __BEGIN_DECLS
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#endif

#ifndef __FBSDID
#define __FBSDID(value)
#endif

#ifndef __RCSID
#define __RCSID(value)
#endif

#ifndef __printf0like
#define __printf0like(format_index, first_argument) \
    __attribute__((__format__(__printf__, format_index, first_argument)))
#endif

#ifndef __nonstring
#define __nonstring __attribute__((__nonstring__))
#endif

#endif
