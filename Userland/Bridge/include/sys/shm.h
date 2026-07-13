#ifndef MIXTAR_BRIDGE_SYS_SHM_H
#define MIXTAR_BRIDGE_SYS_SHM_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_IPCS_COMPAT)

#include <sys/ipc.h>
#include <sys/types.h>
#include <time.h>

struct shmid_ds {
	struct ipc_perm shm_perm;
	size_t shm_segsz;
	time_t shm_atime;
	time_t shm_dtime;
	time_t shm_ctime;
	pid_t shm_cpid;
	pid_t shm_lpid;
	unsigned int shm_nattch;
};

struct shminfo {
	int shmmax;
	int shmmin;
	int shmmni;
	int shmseg;
	int shmall;
};

struct shm_sysctl_info {
	struct shminfo shminfo;
	struct shmid_ds shmids[];
};

#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#include_next <sys/shm.h>
#pragma GCC diagnostic pop
#endif

#endif
