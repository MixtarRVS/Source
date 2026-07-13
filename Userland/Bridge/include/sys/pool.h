#ifndef MIXTAR_BRIDGE_SYS_POOL_H
#define MIXTAR_BRIDGE_SYS_POOL_H
#pragma GCC system_header

#include <stdint.h>

#ifndef SIMPLEQ_FIRST
#define SIMPLEQ_FIRST(head) ((head)->sqh_first)
#endif
#ifndef SIMPLEQ_NEXT
#define SIMPLEQ_NEXT(elm, field) ((elm)->field.sqe_next)
#endif
#ifndef SIMPLEQ_HEAD
#define SIMPLEQ_HEAD(name, type) struct name { struct type *sqh_first; struct type **sqh_last; }
#endif

struct pool {
	char *pr_wchan;
	unsigned long pr_nget;
	unsigned long pr_nput;
	unsigned int pr_npages;
	unsigned int pr_size;
	unsigned int pr_pgsize;
	unsigned int pr_hiwat;
	unsigned long pr_nout;
	unsigned long pr_nfail;
	unsigned int pr_itemsperpage;
	unsigned int pr_minpages;
	unsigned int pr_maxpages;
	unsigned int pr_hardlimit;
	unsigned long pr_nitems;
	unsigned long pr_npagealloc;
	unsigned long pr_npagefree;
	unsigned long pr_nidle;
	struct {
		struct pool *sqe_next;
	} pr_poollist;
};

struct kinfo_pool {
	unsigned long pr_nget;
	unsigned long pr_nput;
	unsigned int pr_npages;
	unsigned int pr_size;
	unsigned int pr_pgsize;
	unsigned int pr_hiwat;
	unsigned long pr_nout;
	unsigned long pr_nfail;
	unsigned int pr_itemsperpage;
	unsigned int pr_minpages;
	unsigned int pr_maxpages;
	unsigned int pr_hardlimit;
	unsigned long pr_nitems;
	unsigned long pr_npagealloc;
	unsigned long pr_npagefree;
	unsigned long pr_nidle;
};

#endif
