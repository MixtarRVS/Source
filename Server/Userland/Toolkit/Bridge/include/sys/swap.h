#ifndef MIXTAR_BRIDGE_SYS_SWAP_H
#define MIXTAR_BRIDGE_SYS_SWAP_H

#include <errno.h>

#define SWAP_NSWAP 1
#define SWAP_STATS 2
#define SWAP_ON 3
#define SWAP_OFF 4
#define SWAP_CTL 5
#define SWF_ENABLE 0x0001

struct swapent {
	char se_path[1024];
	int se_nblks;
	int se_inuse;
	int se_priority;
	int se_flags;
};

static inline int
swapctl(int cmd, const void *arg, int misc)
{
	(void)arg;
	(void)misc;
	if (cmd == SWAP_NSWAP)
		return 0;
	if (cmd == SWAP_STATS)
		return 0;
	errno = EPERM;
	return -1;
}

#endif /* MIXTAR_BRIDGE_SYS_SWAP_H */
