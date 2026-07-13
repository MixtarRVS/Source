#ifndef MIXTAR_BRIDGE_SYS_SEM_H
#define MIXTAR_BRIDGE_SYS_SEM_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_IPCS_COMPAT)

#include <sys/ipc.h>
#include <sys/types.h>
#include <time.h>

struct semid_ds {
	struct ipc_perm sem_perm;
	time_t sem_otime;
	time_t sem_ctime;
	unsigned short sem_nsems;
};

struct seminfo {
	int semmni;
	int semmns;
	int semmnu;
	int semmsl;
	int semopm;
	int semume;
	int semusz;
	int semvmx;
	int semaem;
};

struct sem_sysctl_info {
	struct seminfo seminfo;
	struct semid_ds semids[];
};

#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#include_next <sys/sem.h>
#pragma GCC diagnostic pop
#endif

#endif
