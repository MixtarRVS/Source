#ifndef MIXTAR_BRIDGE_SYS_MTIO_H
#define MIXTAR_BRIDGE_SYS_MTIO_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_MT_COMPAT)

#include <sys/ioctl.h>

struct mtop {
	short mt_op;
	int mt_count;
};

struct mtget {
	int mt_type;
	int mt_resid;
	int mt_dsreg;
	int mt_erreg;
	int mt_blksiz;
	int mt_mblksiz;
	int mt_density;
	int mt_mdensity;
	int mt_fileno;
	int mt_blkno;
};

#define MTWEOF 0
#define MTFSF 1
#define MTBSF 2
#define MTFSR 3
#define MTBSR 4
#define MTREW 5
#define MTOFFL 6
#define MTNOP 7
#define MTRETEN 8
#define MTERASE 9
#define MTEOM 10
#define MTSETBSIZ 11
#define MTSETDNSTY 12

#ifndef MTIOCTOP
#define MTIOCTOP 0x6d01
#endif
#ifndef MTIOCGET
#define MTIOCGET 0x6d02
#endif

#else
#include_next <sys/mtio.h>
#endif

#endif
