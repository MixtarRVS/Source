#ifndef MIXTAR_BRIDGE_SYS_GMON_H
#define MIXTAR_BRIDGE_SYS_GMON_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_GPROF_COMPAT)

#define GMONVERSION 0x00051879
#define GPROF_STATE 0
#define GMON_PROF_OFF 0

struct gmonhdr {
	void *lpc;
	void *hpc;
	int ncnt;
	int version;
	int profrate;
};

struct rawarc {
	unsigned long raw_frompc;
	unsigned long raw_selfpc;
	long raw_count;
};

#else
#include_next <sys/gmon.h>
#endif

#endif
