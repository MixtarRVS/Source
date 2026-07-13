#ifndef MIXTAR_BRIDGE_SYS_IPC_H
#define MIXTAR_BRIDGE_SYS_IPC_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_IPCS_COMPAT)

#include <sys/types.h>

#ifndef IPC_PRIVATE
#define IPC_PRIVATE ((key_t)0)
#endif

struct ipc_perm {
	key_t key;
	uid_t uid;
	gid_t gid;
	uid_t cuid;
	gid_t cgid;
	mode_t mode;
	unsigned short seq;
};

#ifndef IXSEQ_TO_IPCID
#define IXSEQ_TO_IPCID(ix, perm) ((int)(ix) | ((int)((perm).seq) << 16))
#endif

#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#include_next <sys/ipc.h>
#pragma GCC diagnostic pop
#endif

#endif
