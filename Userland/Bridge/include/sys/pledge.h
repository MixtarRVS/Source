#ifndef MIXTAR_BRIDGE_SYS_PLEDGE_H
#define MIXTAR_BRIDGE_SYS_PLEDGE_H

/*
 * The bridge exposes pledge(2) through mixtar_bridge_compat.h.  This header
 * exists so OpenBSD tools that include <sys/pledge.h> compile unchanged.
 */
#ifdef PLEDGENAMES
struct pledgename {
	unsigned int bits;
	const char *name;
};

static const struct pledgename pledgenames[] = {
	{ 1u << 0, "stdio" },
	{ 1u << 1, "rpath" },
	{ 1u << 2, "wpath" },
	{ 1u << 3, "cpath" },
	{ 1u << 4, "tmppath" },
	{ 1u << 5, "inet" },
	{ 1u << 6, "dns" },
	{ 1u << 7, "proc" },
	{ 1u << 8, "exec" },
	{ 0, NULL },
};
#endif

#endif
