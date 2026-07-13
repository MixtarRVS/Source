/* Mixtar Bridge nl_types wrapper.
 *
 * glibc intentionally hides the OpenBSD/NetBSD message-catalog file layout.
 * OpenBSD gencat needs those private structs when _NLS_PRIVATE is set.
 */
#ifndef MIXTAR_BRIDGE_NL_TYPES_H
#define MIXTAR_BRIDGE_NL_TYPES_H

#include <stdint.h>

#ifdef _NLS_PRIVATE
#ifndef _NLS_MAGIC
#define _NLS_MAGIC 0xff88ff89
#endif

struct _nls_cat_hdr {
	int32_t __magic;
	int32_t __nsets;
	int32_t __mem;
	int32_t __msg_hdr_offset;
	int32_t __msg_txt_offset;
};

struct _nls_set_hdr {
	int32_t __setno;
	int32_t __nmsgs;
	int32_t __index;
};

struct _nls_msg_hdr {
	int32_t __msgno;
	int32_t __msglen;
	int32_t __offset;
};
#endif

#ifndef NL_SETD
#define NL_SETD 1
#endif
#ifndef NL_CAT_LOCALE
#define NL_CAT_LOCALE 1
#endif

typedef struct _nl_catd {
	void *__data;
	int __size;
} *nl_catd;

typedef long nl_item;

#ifndef __BEGIN_DECLS
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#endif

__BEGIN_DECLS
extern nl_catd catopen(const char *, int);
extern char *catgets(nl_catd, int, int, const char *);
extern int catclose(nl_catd);
__END_DECLS

#endif
