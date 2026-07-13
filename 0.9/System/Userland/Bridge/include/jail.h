#ifndef MIXTAR_BRIDGE_JAIL_H
#define MIXTAR_BRIDGE_JAIL_H

#include <errno.h>

static const char jail_errmsg[] = "FreeBSD jail lookup is not available on Linux";

static inline int
jail_getid(const char *name)
{
	(void)name;
	errno = ENOTSUP;
	return -1;
}

#endif /* MIXTAR_BRIDGE_JAIL_H */
