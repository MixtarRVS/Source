#ifndef MIXTAR_BRIDGE_SYS_DISK_H
#define MIXTAR_BRIDGE_SYS_DISK_H
#pragma GCC system_header

#include <sys/time.h>
#include <sys/types.h>
#include <stdint.h>

#ifndef TAILQ_FIRST
#define TAILQ_FIRST(head) ((head)->tqh_first)
#endif
#ifndef TAILQ_NEXT
#define TAILQ_NEXT(elm, field) ((elm)->field.tqe_next)
#endif

struct diskstats {
	uint64_t ds_rxfer;
	uint64_t ds_wxfer;
	uint64_t ds_seek;
	uint64_t ds_rbytes;
	uint64_t ds_wbytes;
	struct timeval ds_time;
};

struct disk {
	char *dk_name;
	uint64_t dk_rxfer;
	uint64_t dk_wxfer;
	uint64_t dk_seek;
	uint64_t dk_rbytes;
	uint64_t dk_wbytes;
	struct timeval dk_time;
	struct {
		struct disk *tqe_next;
		struct disk **tqe_prev;
	} dk_link;
};

struct disklist_head {
	struct disk *tqh_first;
	struct disk **tqh_last;
};

#endif
