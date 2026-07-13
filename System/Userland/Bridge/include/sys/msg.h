#ifndef MIXTAR_BRIDGE_SYS_MSG_H
#define MIXTAR_BRIDGE_SYS_MSG_H
#pragma GCC system_header

#if defined(__linux__) && defined(MIXTAR_BRIDGE_IPCS_COMPAT)

#include <sys/ipc.h>
#include <sys/types.h>
#include <time.h>

struct msqid_ds {
	struct ipc_perm msg_perm;
	time_t msg_stime;
	time_t msg_rtime;
	time_t msg_ctime;
	unsigned long msg_cbytes;
	unsigned long msg_qnum;
	unsigned long msg_qbytes;
	pid_t msg_lspid;
	pid_t msg_lrpid;
};

struct msginfo {
	int msgmax;
	int msgmni;
	int msgmnb;
	int msgtql;
	int msgssz;
	int msgseg;
};

struct que {
	struct msqid_ds msqid_ds;
	int que_ix;
	struct {
		struct que *tqe_next;
		struct que **tqe_prev;
	} que_next;
};

struct msg_sysctl_info {
	struct msginfo msginfo;
	struct msqid_ds msgids[];
};

#ifndef TAILQ_NEXT
#define TAILQ_NEXT(elm, field) ((elm)->field.tqe_next)
#endif

#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#include_next <sys/msg.h>
#pragma GCC diagnostic pop
#endif

#endif
