#ifndef MIXTAR_BRIDGE_SYS_UCRED_H
#define MIXTAR_BRIDGE_SYS_UCRED_H

#include <sys/types.h>

struct xucred {
	uid_t cr_uid;
	short cr_ngroups;
	gid_t cr_groups[16];
};

#endif
