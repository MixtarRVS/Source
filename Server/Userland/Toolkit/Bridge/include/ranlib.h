#ifndef MIXTAR_BRIDGE_RANLIB_H
#define MIXTAR_BRIDGE_RANLIB_H

#include <stdint.h>

/*
 * BSD archive symbol table entry.  Linux systems usually do not ship
 * <ranlib.h>, but OpenBSD nm(1) only needs the layout while parsing ar
 * indexes.
 */
struct ranlib {
	union {
		uint32_t ran_strx;
		char *ran_name;
	} ran_un;
	uint32_t ran_off;
};

#endif
