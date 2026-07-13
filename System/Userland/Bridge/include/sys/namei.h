#ifndef MIXTAR_BRIDGE_SYS_NAMEI_H
#define MIXTAR_BRIDGE_SYS_NAMEI_H
#pragma GCC system_header

#include <stdint.h>

struct nchstats {
	uint64_t ncs_goodhits;
	uint64_t ncs_neghits;
	uint64_t ncs_badhits;
	uint64_t ncs_falsehits;
	uint64_t ncs_miss;
	uint64_t ncs_long;
	uint64_t ncs_pass2;
	uint64_t ncs_2passes;
	uint64_t ncs_revhits;
	uint64_t ncs_revmiss;
	uint64_t ncs_dothits;
	uint64_t ncs_dotdothits;
};

#endif
