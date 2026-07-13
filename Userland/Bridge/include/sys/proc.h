#ifndef MIXTAR_BRIDGE_SYS_PROC_H
#define MIXTAR_BRIDGE_SYS_PROC_H

#include <sys/resource.h>
#include <sys/types.h>
#include <stdint.h>

typedef uint32_t fixpt_t;

#ifndef MAXCOMLEN
#define MAXCOMLEN 24
#endif

#ifndef LOGIN_NAME_MAX
#define LOGIN_NAME_MAX 17
#endif

#ifndef NGROUPS
#define NGROUPS 16
#endif

#define KERN_PROC_ALL 0
#define KERN_PROC_PID 1
#define KERN_PROC_PGRP 2
#define KERN_PROC_SESSION 3
#define KERN_PROC_TTY 4
#define KERN_PROC_UID 5
#define KERN_PROC_KTHREAD 6
#define KERN_PROC_SHOW_THREADS 0x40000000
#define KERN_PROC_CWD 72

#ifndef RT_TABLEID_MAX
#define RT_TABLEID_MAX 255
#endif

#define PS_CONTROLT 0x00000001
#define PS_TRACED 0x00000002
#define PS_EXITING 0x00000004
#define PS_ZOMBIE 0x00000008
#define PS_EMBRYO 0x00000000
#define PS_ISPWAIT 0x00000010
#define PS_PLEDGE 0x00000020
#define PS_CHROOT 0x00000040

#define P_SINTR 0x00000001
#define P_SYSTEM 0x00000002

#define EPROC_SLEADER 0x00000001
#define EPROC_UNVEIL 0x00000002
#define EPROC_LKUNVEIL 0x00000004
#define EPROC_CTTY 0x00000008

#define KI_NOCPU (~0ULL)
#define PZERO 22

#define SIDL 1
#define SRUN 2
#define SSLEEP 3
#define SSTOP 4
#define SZOMB 5
#define SDEAD 6
#define SONPROC 7

struct kinfo_proc {
	pid_t p_pid;
	pid_t p_tid;
	pid_t p_ppid;
	pid_t p__pgid;
	pid_t p_sid;
	pid_t p_tpgid;
	dev_t p_tdev;
	uid_t p_uid;
	uid_t p_ruid;
	uid_t p_svuid;
	gid_t p_gid;
	gid_t p_rgid;
	gid_t p_svgid;
	gid_t p_groups[NGROUPS];
	short p_ngroups;
	uint32_t p_rtableid;
	uint32_t p_psflags;
	uint32_t p_flag;
	uint32_t p_estcpu;
	uint64_t p_cpuid;
	uint32_t p_acflag;
	uint32_t p_jobc;
	uint64_t p_paddr;
	uint64_t p_back;
	uint64_t p_ru;
	uint64_t p_wchan;
	uint32_t p_sigcatch;
	uint32_t p_sigignore;
	uint32_t p_siglist;
	uint32_t p_sigmask;
	uint32_t p_slptime;
	uint32_t p_swtime;
	uint32_t p_traceflag;
	uint64_t p_tracep;
	uint64_t p_tsess;
	uint32_t p_xstat;
	uint8_t p_usrpri;
	int p_nice;
	int p_priority;
	int p_stat;
	int p_eflag;
	uint32_t p_pledge;
	int p_uvalid;
	unsigned int p_ustart_sec;
	unsigned int p_ustart_usec;
	unsigned int p_rtime_sec;
	unsigned int p_rtime_usec;
	unsigned int p_uctime_sec;
	unsigned int p_uctime_usec;
	unsigned long p_vm_tsize;
	unsigned long p_vm_dsize;
	unsigned long p_vm_ssize;
	unsigned long p_vm_rssize;
	unsigned long p_rssize;
	unsigned long p_rlim_rss_cur;
	unsigned long p_pctcpu;
	unsigned long p_uru_inblock;
	unsigned long p_uru_majflt;
	unsigned long p_uru_maxrss;
	unsigned long p_uru_minflt;
	unsigned long p_uru_msgrcv;
	unsigned long p_uru_msgsnd;
	unsigned long p_uru_nivcsw;
	unsigned long p_uru_nsignals;
	unsigned long p_uru_nswap;
	unsigned long p_uru_nvcsw;
	unsigned long p_uru_oublock;
	char p_comm[MAXCOMLEN + 1];
	char p_name[MAXCOMLEN + 1];
	char p_wmesg[9];
	char p_login[LOGIN_NAME_MAX];
};

struct forkstat {
	unsigned int cntfork;
	unsigned long long sizfork;
	unsigned int cntvfork;
	unsigned long long sizvfork;
	unsigned int cnttfork;
	unsigned long long siztfork;
	unsigned int cntkthread;
	unsigned long long sizkthread;
};

#endif
