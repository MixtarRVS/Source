#ifndef MIXTAR_BRIDGE_SYS_REBOOT_H
#define MIXTAR_BRIDGE_SYS_REBOOT_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_REBOOT_COMPAT)

#include <errno.h>

#define RB_AUTOBOOT 0x0000
#define RB_ASKNAME 0x0001
#define RB_SINGLE 0x0002
#define RB_NOSYNC 0x0004
#define RB_HALT 0x0008
#define RB_INITNAME 0x0010
#define RB_DFLTROOT 0x0020
#define RB_KDB 0x0040
#define RB_RDONLY 0x0080
#define RB_DUMP 0x0100
#define RB_MINIROOT 0x0200
#define RB_CONFIG 0x0400
#define RB_POWERDOWN 0x0800

static inline int
reboot(int howto)
{
	(void)howto;
	errno = EPERM;
	return -1;
}

#else
#include_next <sys/reboot.h>
#endif

#endif
