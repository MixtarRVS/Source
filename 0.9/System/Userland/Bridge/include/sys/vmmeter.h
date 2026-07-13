#ifndef MIXTAR_BRIDGE_SYS_VMMETER_H
#define MIXTAR_BRIDGE_SYS_VMMETER_H
#pragma GCC system_header

#include <stdint.h>

struct uvmexp {
	uint32_t pagesize;
	uint32_t npages;
	uint32_t free;
	uint32_t active;
	uint32_t inactive;
	uint32_t paging;
	uint32_t wired;
	uint32_t zeropages;
	uint32_t reserve_pagedaemon;
	uint32_t reserve_kernel;
	uint32_t percpucaches;
	uint32_t pcphit;
	uint32_t pcpmiss;
	uint32_t swpages;
	uint32_t swpginuse;
	uint32_t faults;
	uint32_t traps;
	uint32_t intrs;
	uint32_t swtch;
	uint32_t fpswtch;
	uint32_t softs;
	uint32_t syscalls;
	uint32_t pageins;
	uint32_t forks;
	uint32_t forks_sharevm;
	uint32_t kmapent;
	uint32_t pga_zerohit;
	uint32_t pga_zeromiss;
	uint32_t pdwoke;
	uint32_t pdrevs;
	uint32_t pdfreed;
	uint32_t pdscans;
	uint32_t pdreact;
	uint32_t pdbusy;
	uint32_t pdpageouts;
};

struct vmtotal {
	int t_rq;
	int t_dw;
	int t_pw;
	int t_sl;
	int t_sw;
};

#endif
