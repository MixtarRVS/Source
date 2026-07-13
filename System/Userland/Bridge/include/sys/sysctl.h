#ifndef MIXTAR_BRIDGE_SYS_SYSCTL_H
#define MIXTAR_BRIDGE_SYS_SYSCTL_H

#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#if defined(__linux__) && defined(MIXTAR_BRIDGE_IPCS_COMPAT)
#include <sys/msg.h>
#include <sys/sem.h>
#include <sys/shm.h>
#endif
#include <sys/proc.h>
#include <sys/utsname.h>
#include <sys/vmmeter.h>
#include <unistd.h>

#define CTLTYPE_NODE 1
#define CTLTYPE_INT 2
#define CTLTYPE_STRING 3
#define CTLTYPE_QUAD 4
#define CTLTYPE_STRUCT 5
#define CTLTYPE_OPAQUE 6
#define CTLTYPE_LONG 7

struct ctlname {
	char *ctl_name;
	int ctl_type;
};

#define CTL_UNSPEC 0
#define CTL_KERN 1
#define CTL_VM 2
#define CTL_FS 3
#define CTL_NET 4
#define CTL_DEBUG 5
#define CTL_HW 6
#define CTL_MACHDEP 7
#define CTL_USER 8
#define CTL_DDB 9
#define CTL_VFS 10
#define CTL_MAXID 11
#define CTL_MAXNAME 12

#define KERN_OSTYPE 1
#define KERN_OSRELEASE 2
#define KERN_OSREV 3
#define KERN_VERSION 4
#define KERN_MAXVNODES 5
#define KERN_MAXPROC 6
#define KERN_MAXFILES 7
#define KERN_ARGMAX 8
#define KERN_SECURELVL 9
#define KERN_HOSTNAME 10
#define KERN_HOSTID 11
#define KERN_MSGBUFSIZE 38
#define KERN_MSGBUF 39
#define KERN_PROF 40
#define KERN_CONSBUFSIZE 83
#define KERN_CONSBUF 84
#define KERN_CONSDEV 85
#define KERN_CLOCKRATE 12
#define KERN_PROC 14
#define KERN_BOOTTIME 21
#define KERN_FSCALE 27
#define KERN_CCPU 45
#define KERN_FILE 50
#define KERN_PROC_ARGS 55
#define KERN_CPTIME 64
#define KERN_TTY 65
#define KERN_TTY_TKNIN 1
#define KERN_TTY_TKNOUT 2
#define KERN_NCHSTATS 66
#define KERN_FORKSTAT 67
#define KERN_POOL 68
#define KERN_POOL_NPOOLS 1
#define KERN_POOL_POOL 2
#define KERN_POOL_NAME 3
#define KERN_INTRCNT 69
#define KERN_INTRCNT_NUM 1
#define KERN_INTRCNT_NAME 2
#define KERN_INTRCNT_VECTOR 3
#define KERN_INTRCNT_CNT 4
#define KERN_MALLOCSTATS 70
#define KERN_MALLOC_BUCKETS 1
#define KERN_MALLOC_BUCKET 2
#define KERN_MALLOC_KMEMSTATS 3
#define KERN_MBSTAT 71
#define KERN_SEMINFO 72
#define KERN_SHMINFO 73
#define KERN_WATCHDOG 74
#define KERN_TIMECOUNTER 75
#define KERN_NETLIVELOCKS 76
#define KERN_SOMAXCONN 77
#define KERN_SOMINCONN 78
#define KERN_AUDIO 79
#define KERN_VIDEO 80
#define KERN_WITNESS 81
#define KERN_PFSTATUS 82
#define KERN_TIMEOUT_STATS 86
#define KERN_CPUSTATS 87
#define KERN_SYSVMSG 60
#define KERN_SYSVSHM 61
#define KERN_SYSVSEM 62
#define KERN_SYSVIPC_INFO 63
#define KERN_SYSVIPC_MSG_INFO 1
#define KERN_SYSVIPC_SHM_INFO 2
#define KERN_SYSVIPC_SEM_INFO 3
#define KERN_PROC_ARGV 1
#define KERN_MAXID 88

#define HW_MACHINE 1
#define HW_MODEL 2
#define HW_NCPU 3
#define HW_NCPUONLINE 31
#define HW_BYTEORDER 4
#define HW_PHYSMEM 5
#define HW_USERMEM 6
#define HW_PAGESIZE 7
#define HW_DISKCOUNT 25
#define HW_DISKNAMES 26
#define HW_DISKSTATS 27
#define HW_SENSORS 28
#define HW_BATTERY 29
#define HW_SMT 30
#define HW_USERMEM64 24
#define HW_PHYSMEM64 HW_USERMEM64
#define HW_MAXID 32

#define VM_MAXSLP 17
#define VM_UVMEXP 18
#define VM_METER 19
#define VM_LOADAVG 20
#define VM_PSSTRINGS 21
#define VM_SWAPENCRYPT 22
#define VM_NKMEMPAGES 23
#define VM_ANONMIN 24
#define VM_VTEXTMIN 25
#define VM_VNODEMIN 26
#define VM_MALLOC_CONF 27
#define VM_MAXID 28

#define NET_MAXID 16
#define DBCTL_MAXID 1
#define CTL_DEBUG_MAXID 1
#define IPV6PROTO_MAXID 1
#define IPV6CTL_MAXID 1
#define ICMPV6CTL_MAXID 1
#define NET_UNIX_MAXID 1
#define NET_UNIX_PROTO_MAXID 1
#define NET_LINK_MAXID 1
#define NET_LINK_IFRXQ 0
#define NET_LINK_IFRXQ_MAXID 1
#define MPLSCTL_MAXID 1
#define PIPEXCTL_MAXID 1
#define BPFCTL_MAXID 1

struct _ps_strings {
	void *val;
	char **ps_argvstr;
	int ps_nargvstr;
	char **ps_envstr;
	int ps_nenvstr;
};

#ifndef IPPROTO_ETHERIP
#define IPPROTO_ETHERIP 97
#endif
#ifndef IPPROTO_IPCOMP
#define IPPROTO_IPCOMP 108
#endif
#ifndef IPPROTO_CARP
#define IPPROTO_CARP 112
#endif
#ifndef IPPROTO_PFSYNC
#define IPPROTO_PFSYNC 240
#endif
#ifndef IPPROTO_DIVERT
#define IPPROTO_DIVERT 254
#endif

#ifndef PF_LINK
#define PF_LINK 18
#endif
#ifndef PF_BPF
#define PF_BPF 23
#endif
#ifndef PF_PIPEX
#define PF_PIPEX 24
#endif

#define IPPROTO_MAXID 256
#define IPCTL_MAXID 16
#define ICMPCTL_MAXID 8
#define IGMPCTL_MAXID 8
#define IPIPCTL_MAXID 8
#define TCPCTL_MAXID 16
#define UDPCTL_MAXID 8
#define GRECTL_MAXID 8
#define ESPCTL_MAXID 8
#define AHCTL_MAXID 8
#define ETHERIPCTL_MAXID 8
#define IPCOMPCTL_MAXID 8
#define CARPCTL_MAXID 8
#define PFSYNCCTL_MAXID 8
#define DIVERTCTL_MAXID 8
#define NET_BPF_MAXID 8
#define IFQCTL_MAXID 8

#define IPCTL_STATS 1
#define IPCTL_MRTSTATS 2
#define IPCTL_MRTMFC 3
#define IPCTL_MRTVIF 4
#define ICMPCTL_STATS 1
#define IGMPCTL_STATS 1
#define IPIPCTL_STATS 1
#define TCPCTL_STATS 1
#define TCPCTL_BADDYNAMIC 2
#define TCPCTL_ROOTONLY 3
#define UDPCTL_STATS 1
#define UDPCTL_BADDYNAMIC 2
#define UDPCTL_ROOTONLY 3
#define GRECTL_STATS 1
#define ESPCTL_STATS 1
#define AHCTL_STATS 1
#define ETHERIPCTL_STATS 1
#define IPCOMPCTL_STATS 1
#define CARPCTL_STATS 1
#define PFSYNCCTL_STATS 1
#define DIVERTCTL_STATS 1
#define IPV6CTL_MRTMFC 1
#define IPV6CTL_MRTMIF 2

#define CTL_DEBUG_NAME 1
#define CTL_DEBUG_VALUE 2

#define KERN_MALLOC_MAXID 8
#define KERN_MALLOC_KMEMNAMES 4
#define KERN_FORKSTAT_MAXID 9
#define KERN_FORKSTAT_FORK 1
#define KERN_FORKSTAT_VFORK 2
#define KERN_FORKSTAT_TFORK 3
#define KERN_FORKSTAT_KTHREAD 4
#define KERN_FORKSTAT_SIZFORK 5
#define KERN_FORKSTAT_SIZVFORK 6
#define KERN_FORKSTAT_SIZTFORK 7
#define KERN_FORKSTAT_SIZKTHREAD 8
#define KERN_NCHSTATS_MAXID 13
#define KERN_NCHSTATS_GOODHITS 1
#define KERN_NCHSTATS_NEGHITS 2
#define KERN_NCHSTATS_BADHITS 3
#define KERN_NCHSTATS_FALSEHITS 4
#define KERN_NCHSTATS_MISS 5
#define KERN_NCHSTATS_LONG 6
#define KERN_NCHSTATS_PASS2 7
#define KERN_NCHSTATS_2PASSES 8
#define KERN_NCHSTATS_REVHITS 9
#define KERN_NCHSTATS_REVMISS 10
#define KERN_NCHSTATS_DOTHITS 11
#define KERN_NCHSTATS_DOTDOTHITS 12
#define KERN_TTY_MAXID 3
#define KERN_SEMINFO_MAXID 1
#define KERN_SHMINFO_MAXID 1
#define KERN_WATCHDOG_MAXID 1
#define KERN_TIMECOUNTER_MAXID 1
#define KERN_AUDIO_MAXID 1
#define KERN_VIDEO_MAXID 1
#define KERN_WITNESS_MAXID 1
#define HW_BATTERY_MAXID 1

#define DP_MAPSIZE 2048
#define DP_SET(map, port) ((map)[(port) / 32] |= (1U << ((port) % 32)))
#define DP_CLR(map, port) ((map)[(port) / 32] &= ~(1U << ((port) % 32)))
#define DP_ISSET(map, port) (((map)[(port) / 32] & (1U << ((port) % 32))) != 0)

struct timeoutstat {
	unsigned long long tos_added;
	unsigned long long tos_cancelled;
	unsigned long long tos_deleted;
	unsigned long long tos_late;
	unsigned long long tos_pending;
	unsigned long long tos_readded;
	unsigned long long tos_scheduled;
	unsigned long long tos_rescheduled;
	unsigned long long tos_run_softclock;
	unsigned long long tos_run_thread;
	unsigned long long tos_softclocks;
	unsigned long long tos_thread_wakeups;
};

#ifndef CPUSTATES
#define CPUSTATES 6
#endif

#define CPUSTATS_ONLINE 0x0001

struct cpustats {
	int64_t cs_time[CPUSTATES];
	int cs_flags;
};

struct loadavg {
	long ldavg[3];
	long fscale;
};

struct bcachestats {
	int numbufpages;
};

#define MIXTAR_CTL_NULL { NULL, 0 }
#define MIXTAR_CTL(name, type) { (char *)(name), (type) }

#define CTL_NAMES { \
	MIXTAR_CTL_NULL, \
	MIXTAR_CTL("kern", CTLTYPE_NODE), \
	MIXTAR_CTL("vm", CTLTYPE_NODE), \
	MIXTAR_CTL_NULL, \
	MIXTAR_CTL("net", CTLTYPE_NODE), \
	MIXTAR_CTL("debug", CTLTYPE_NODE), \
	MIXTAR_CTL("hw", CTLTYPE_NODE), \
	MIXTAR_CTL("machdep", CTLTYPE_NODE), \
	MIXTAR_CTL("user", CTLTYPE_NODE), \
	MIXTAR_CTL("ddb", CTLTYPE_NODE), \
	MIXTAR_CTL("vfs", CTLTYPE_NODE) \
}

#define CTL_KERN_NAMES { \
	MIXTAR_CTL_NULL, \
	MIXTAR_CTL("ostype", CTLTYPE_STRING), \
	MIXTAR_CTL("osrelease", CTLTYPE_STRING), \
	MIXTAR_CTL("osrevision", CTLTYPE_INT), \
	MIXTAR_CTL("version", CTLTYPE_STRING), \
	MIXTAR_CTL("maxvnodes", CTLTYPE_INT), \
	MIXTAR_CTL("maxproc", CTLTYPE_INT), \
	MIXTAR_CTL("maxfiles", CTLTYPE_INT), \
	MIXTAR_CTL("argmax", CTLTYPE_INT), \
	MIXTAR_CTL("securelevel", CTLTYPE_INT), \
	MIXTAR_CTL("hostname", CTLTYPE_STRING), \
	MIXTAR_CTL("hostid", CTLTYPE_INT), \
	MIXTAR_CTL("clockrate", CTLTYPE_STRUCT), \
	MIXTAR_CTL_NULL, \
	MIXTAR_CTL("proc", CTLTYPE_NODE), \
	[27] = MIXTAR_CTL("fscale", CTLTYPE_INT), \
	[38] = MIXTAR_CTL("msgbufsize", CTLTYPE_INT), \
	[39] = MIXTAR_CTL("msgbuf", CTLTYPE_STRUCT), \
	[40] = MIXTAR_CTL("prof", CTLTYPE_STRUCT), \
	[45] = MIXTAR_CTL("ccpu", CTLTYPE_INT), \
	[50] = MIXTAR_CTL("file", CTLTYPE_STRUCT), \
	[55] = MIXTAR_CTL("procargs", CTLTYPE_NODE), \
	[60] = MIXTAR_CTL("sysvmsg", CTLTYPE_INT), \
	[61] = MIXTAR_CTL("sysvshm", CTLTYPE_INT), \
	[62] = MIXTAR_CTL("sysvsem", CTLTYPE_INT), \
	[63] = MIXTAR_CTL("sysvipc_info", CTLTYPE_NODE), \
	[64] = MIXTAR_CTL("cptime", CTLTYPE_STRUCT), \
	[65] = MIXTAR_CTL("tty", CTLTYPE_NODE), \
	[66] = MIXTAR_CTL("nchstats", CTLTYPE_NODE), \
	[67] = MIXTAR_CTL("forkstat", CTLTYPE_NODE), \
	[69] = MIXTAR_CTL("intrcnt", CTLTYPE_NODE), \
	[70] = MIXTAR_CTL("malloc", CTLTYPE_NODE), \
	[72] = MIXTAR_CTL("seminfo", CTLTYPE_NODE), \
	[73] = MIXTAR_CTL("shminfo", CTLTYPE_NODE), \
	[74] = MIXTAR_CTL("watchdog", CTLTYPE_NODE), \
	[75] = MIXTAR_CTL("timecounter", CTLTYPE_NODE), \
	[77] = MIXTAR_CTL("somaxconn", CTLTYPE_INT), \
	[78] = MIXTAR_CTL("sominconn", CTLTYPE_INT), \
	[79] = MIXTAR_CTL("audio", CTLTYPE_NODE), \
	[80] = MIXTAR_CTL("video", CTLTYPE_NODE), \
	[81] = MIXTAR_CTL("witness", CTLTYPE_NODE), \
	[82] = MIXTAR_CTL("pfstatus", CTLTYPE_STRUCT), \
	[83] = MIXTAR_CTL("consbufsize", CTLTYPE_INT), \
	[84] = MIXTAR_CTL("consbuf", CTLTYPE_STRUCT), \
	[85] = MIXTAR_CTL("consdev", CTLTYPE_STRUCT), \
	[86] = MIXTAR_CTL("timeout_stats", CTLTYPE_STRUCT), \
	[87] = MIXTAR_CTL("cpustats", CTLTYPE_STRUCT) \
}

#define CTL_VM_NAMES { \
	MIXTAR_CTL_NULL, \
	[17] = MIXTAR_CTL("maxslp", CTLTYPE_INT), \
	[18] = MIXTAR_CTL("uvmexp", CTLTYPE_STRUCT), \
	[19] = MIXTAR_CTL("meter", CTLTYPE_STRUCT), \
	[20] = MIXTAR_CTL("loadavg", CTLTYPE_STRUCT), \
	[21] = MIXTAR_CTL("psstrings", CTLTYPE_STRUCT), \
	[22] = MIXTAR_CTL("swapencrypt", CTLTYPE_NODE), \
	[23] = MIXTAR_CTL("nkmempages", CTLTYPE_INT), \
	[24] = MIXTAR_CTL("anonmin", CTLTYPE_INT), \
	[25] = MIXTAR_CTL("vtextmin", CTLTYPE_INT), \
	[26] = MIXTAR_CTL("vnodemin", CTLTYPE_INT), \
	[27] = MIXTAR_CTL("malloc_conf", CTLTYPE_STRING) \
}

#define CTL_HW_NAMES { \
	MIXTAR_CTL_NULL, \
	MIXTAR_CTL("machine", CTLTYPE_STRING), \
	MIXTAR_CTL("model", CTLTYPE_STRING), \
	MIXTAR_CTL("ncpu", CTLTYPE_INT), \
	MIXTAR_CTL("byteorder", CTLTYPE_INT), \
	MIXTAR_CTL("physmem", CTLTYPE_INT), \
	MIXTAR_CTL("usermem", CTLTYPE_INT), \
	MIXTAR_CTL("pagesize", CTLTYPE_INT), \
	[24] = MIXTAR_CTL("physmem64", CTLTYPE_QUAD), \
	[25] = MIXTAR_CTL("diskcount", CTLTYPE_INT), \
	[26] = MIXTAR_CTL("disknames", CTLTYPE_STRING), \
	[27] = MIXTAR_CTL("diskstats", CTLTYPE_STRUCT), \
	[28] = MIXTAR_CTL("sensors", CTLTYPE_NODE), \
	[29] = MIXTAR_CTL("battery", CTLTYPE_NODE), \
	[30] = MIXTAR_CTL("smt", CTLTYPE_INT), \
	[31] = MIXTAR_CTL("ncpuonline", CTLTYPE_INT) \
}

#define CTL_NET_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("inet", CTLTYPE_NODE), MIXTAR_CTL("inet6", CTLTYPE_NODE), MIXTAR_CTL("unix", CTLTYPE_NODE), MIXTAR_CTL("link", CTLTYPE_NODE), MIXTAR_CTL("bpf", CTLTYPE_NODE), MIXTAR_CTL("mpls", CTLTYPE_NODE), MIXTAR_CTL("pipex", CTLTYPE_NODE) }
#define CTL_DDB_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_MALLOC_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("buckets", CTLTYPE_STRUCT), MIXTAR_CTL("bucket", CTLTYPE_STRUCT), MIXTAR_CTL("kmemstats", CTLTYPE_STRUCT) }
#define CTL_KERN_FORKSTAT_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_NCHSTATS_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_TTY_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("tknin", CTLTYPE_INT), MIXTAR_CTL("tknout", CTLTYPE_INT) }
#define CTL_KERN_SEMINFO_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_SHMINFO_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_WATCHDOG_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_TIMECOUNTER_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_AUDIO_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_VIDEO_NAMES { MIXTAR_CTL_NULL }
#define CTL_KERN_WITNESS_NAMES { MIXTAR_CTL_NULL }
#define CTL_HW_BATTERY_NAMES { MIXTAR_CTL_NULL }
#define CTL_IPV6PROTO_NAMES { MIXTAR_CTL_NULL }
#define IPV6CTL_NAMES { MIXTAR_CTL_NULL }
#define ICMPV6CTL_NAMES { MIXTAR_CTL_NULL }
#define CTL_NET_UNIX_NAMES { MIXTAR_CTL_NULL }
#define CTL_NET_UNIX_PROTO_NAMES { MIXTAR_CTL_NULL }
#define CTL_NET_LINK_NAMES { MIXTAR_CTL_NULL }
#define CTL_NET_LINK_IFRXQ_NAMES { MIXTAR_CTL_NULL }
#define MPLSCTL_NAMES { MIXTAR_CTL_NULL }
#define PIPEXCTL_NAMES { MIXTAR_CTL_NULL }
#define BPFCTL_NAMES { MIXTAR_CTL_NULL }
#define CTL_IPPROTO_NAMES { MIXTAR_CTL_NULL, [IPPROTO_IP] = MIXTAR_CTL("ip", CTLTYPE_NODE), [IPPROTO_ICMP] = MIXTAR_CTL("icmp", CTLTYPE_NODE), [IPPROTO_TCP] = MIXTAR_CTL("tcp", CTLTYPE_NODE), [IPPROTO_UDP] = MIXTAR_CTL("udp", CTLTYPE_NODE), [IPPROTO_IPV6] = MIXTAR_CTL("ipv6", CTLTYPE_NODE) }
#define IPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT), MIXTAR_CTL("mrtstats", CTLTYPE_STRUCT), MIXTAR_CTL("mrtmfc", CTLTYPE_STRUCT), MIXTAR_CTL("mrtvif", CTLTYPE_STRUCT) }
#define ICMPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define IGMPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define IPIPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define TCPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT), MIXTAR_CTL("baddynamic", CTLTYPE_STRUCT), MIXTAR_CTL("rootonly", CTLTYPE_STRUCT) }
#define UDPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT), MIXTAR_CTL("baddynamic", CTLTYPE_STRUCT), MIXTAR_CTL("rootonly", CTLTYPE_STRUCT) }
#define GRECTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define ESPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define AHCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define ETHERIPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define IPCOMPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define CARPCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define PFSYNCCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define DIVERTCTL_NAMES { MIXTAR_CTL_NULL, MIXTAR_CTL("stats", CTLTYPE_STRUCT) }
#define CTL_NET_BPF_NAMES { MIXTAR_CTL_NULL }
#define CTL_IFQ_NAMES { MIXTAR_CTL_NULL }
#define CTL_VFSGENCTL_NAMES { MIXTAR_CTL_NULL }
#define FFS_NAMES { MIXTAR_CTL_NULL }
#define FS_NFS_NAMES { MIXTAR_CTL_NULL }
#define FUSEFS_NAMES { MIXTAR_CTL_NULL }
#define FFS_MAXID 1
#define NFS_MAXID 1
#define FUSEFS_MAXID 1
#define CTL_SWPENC_NAMES { MIXTAR_CTL_NULL }
#define SWPENC_MAXID 1

#ifndef VFS_GENERIC
#define VFS_GENERIC 0
#endif
#ifndef VFS_BCACHESTAT
#define VFS_BCACHESTAT 3
#endif

struct clockinfo {
	int hz;
	int tick;
	int profhz;
	int stathz;
};

struct mixtar_kernel_msgbuf {
	long msg_magic;
	long msg_bufx;
	long msg_bufr;
	long msg_bufs;
	char msg_bufc[];
};

#ifndef MSG_MAGIC
#define MSG_MAGIC 0x063062
#endif

static inline int
sysctl(const int *name, unsigned int namelen, void *oldp, size_t *oldlenp,
    const void *newp, size_t newlen)
{
	(void)newp;
	(void)newlen;
	if (name == NULL || oldlenp == NULL) {
		errno = EINVAL;
		return -1;
	}
#if defined(__linux__) && defined(MIXTAR_BRIDGE_IPCS_COMPAT)
	if (namelen == 2 && name[0] == CTL_KERN &&
	    (name[1] == KERN_SYSVMSG || name[1] == KERN_SYSVSHM ||
	    name[1] == KERN_SYSVSEM)) {
		int valid = 1;
		if (oldp == NULL) {
			errno = EINVAL;
			return -1;
		}
		if (*oldlenp < sizeof(valid)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &valid, sizeof(valid));
		*oldlenp = sizeof(valid);
		return 0;
	}
	if (namelen == 3 && name[0] == CTL_KERN &&
	    name[1] == KERN_SYSVIPC_INFO &&
	    name[2] == KERN_SYSVIPC_MSG_INFO) {
		struct msg_sysctl_info info;
		size_t need = sizeof(info);
		size_t minimum = sizeof(info.msginfo);
		memset(&info, 0, sizeof(info));
		info.msginfo.msgmax = 8192;
		info.msginfo.msgmnb = 16384;
		info.msginfo.msgssz = 16;
		if (oldp == NULL) {
			*oldlenp = need;
			return 0;
		}
		if (*oldlenp < minimum) {
			errno = ENOMEM;
			return -1;
		}
		if (*oldlenp < need)
			need = *oldlenp;
		memcpy(oldp, &info, need);
		*oldlenp = need;
		return 0;
	}
	if (namelen == 3 && name[0] == CTL_KERN &&
	    name[1] == KERN_SYSVIPC_INFO &&
	    name[2] == KERN_SYSVIPC_SHM_INFO) {
		struct shm_sysctl_info info;
		size_t need = sizeof(info);
		size_t minimum = sizeof(info.shminfo);
		memset(&info, 0, sizeof(info));
		info.shminfo.shmmax = 33554432;
		info.shminfo.shmmin = 1;
		info.shminfo.shmseg = 128;
		if (oldp == NULL) {
			*oldlenp = need;
			return 0;
		}
		if (*oldlenp < minimum) {
			errno = ENOMEM;
			return -1;
		}
		if (*oldlenp < need)
			need = *oldlenp;
		memcpy(oldp, &info, need);
		*oldlenp = need;
		return 0;
	}
	if (namelen == 3 && name[0] == CTL_KERN &&
	    name[1] == KERN_SYSVIPC_INFO &&
	    name[2] == KERN_SYSVIPC_SEM_INFO) {
		struct sem_sysctl_info info;
		size_t need = sizeof(info);
		size_t minimum = sizeof(info.seminfo);
		memset(&info, 0, sizeof(info));
		info.seminfo.semmni = 0;
		info.seminfo.semmns = 0;
		info.seminfo.semmnu = 0;
		info.seminfo.semmsl = 250;
		info.seminfo.semopm = 32;
		info.seminfo.semume = 0;
		info.seminfo.semusz = 0;
		info.seminfo.semvmx = 32767;
		info.seminfo.semaem = 16384;
		if (oldp == NULL) {
			*oldlenp = need;
			return 0;
		}
		if (*oldlenp < minimum) {
			errno = ENOMEM;
			return -1;
		}
		if (*oldlenp < need)
			need = *oldlenp;
		memcpy(oldp, &info, need);
		*oldlenp = need;
		return 0;
	}
#endif
	if (oldp == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (namelen == 2 && name[0] == CTL_KERN &&
	    (name[1] == KERN_OSTYPE || name[1] == KERN_OSRELEASE ||
	    name[1] == KERN_VERSION || name[1] == KERN_HOSTNAME)) {
		struct utsname uts;
		const char *value = "Linux";
		size_t need;
		if (uname(&uts) == 0) {
			if (name[1] == KERN_OSTYPE)
				value = uts.sysname;
			else if (name[1] == KERN_OSRELEASE)
				value = uts.release;
			else if (name[1] == KERN_VERSION)
				value = uts.version;
			else if (name[1] == KERN_HOSTNAME)
				value = uts.nodename;
		}
		need = strlen(value) + 1;
		if (*oldlenp < need) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, value, need);
		*oldlenp = need;
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN &&
	    (name[1] == KERN_OSREV || name[1] == KERN_MAXVNODES ||
	    name[1] == KERN_MAXPROC || name[1] == KERN_MAXFILES ||
	    name[1] == KERN_ARGMAX || name[1] == KERN_SECURELVL ||
	    name[1] == KERN_HOSTID || name[1] == KERN_SOMAXCONN ||
	    name[1] == KERN_SOMINCONN)) {
		int value = 0;
		if (name[1] == KERN_ARGMAX) {
			long argmax = sysconf(_SC_ARG_MAX);
			value = argmax > 0 ? (int)argmax : 262144;
		} else if (name[1] == KERN_MAXPROC) {
			value = 32768;
		} else if (name[1] == KERN_MAXFILES) {
			value = 1048576;
		} else if (name[1] == KERN_SOMAXCONN) {
			value = 4096;
		}
		if (*oldlenp < sizeof(value)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &value, sizeof(value));
		*oldlenp = sizeof(value);
		return 0;
	}
	if (namelen == 3 && name[0] == CTL_KERN && name[1] == KERN_CPUSTATS) {
		struct cpustats stats;
		memset(&stats, 0, sizeof(stats));
		stats.cs_time[0] = 1;
		stats.cs_flags = CPUSTATS_ONLINE;
		if (*oldlenp < sizeof(stats)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &stats, sizeof(stats));
		*oldlenp = sizeof(stats);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_HW &&
	    (name[1] == HW_MACHINE || name[1] == HW_MODEL ||
	    name[1] == HW_DISKNAMES)) {
		struct utsname uts;
		const char *value = "";
		size_t need;
		if (uname(&uts) == 0) {
			if (name[1] == HW_MACHINE)
				value = uts.machine;
			else if (name[1] == HW_MODEL)
				value = uts.machine;
		}
		need = strlen(value) + 1;
		if (*oldlenp < need) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, value, need);
		*oldlenp = need;
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_HW &&
	    (name[1] == HW_NCPU || name[1] == HW_BYTEORDER ||
	    name[1] == HW_PHYSMEM || name[1] == HW_USERMEM ||
	    name[1] == HW_PAGESIZE || name[1] == HW_DISKCOUNT ||
	    name[1] == HW_NCPUONLINE || name[1] == HW_SMT)) {
		int value = 0;
		if (name[1] == HW_NCPU || name[1] == HW_NCPUONLINE) {
			long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
			value = ncpu > 0 ? (int)ncpu : 1;
		} else if (name[1] == HW_BYTEORDER) {
			value = 1234;
		} else if (name[1] == HW_PAGESIZE) {
			long pagesize = sysconf(_SC_PAGESIZE);
			value = pagesize > 0 ? (int)pagesize : 4096;
		} else if (name[1] == HW_PHYSMEM || name[1] == HW_USERMEM) {
			long pages = sysconf(_SC_PHYS_PAGES);
			long page_size = sysconf(_SC_PAGESIZE);
			unsigned long long memory = 0;
			if (pages > 0 && page_size > 0)
				memory = (unsigned long long)pages *
				    (unsigned long long)page_size;
			value = memory > 2147483647ULL ? 2147483647 : (int)memory;
		} else if (name[1] == HW_SMT) {
			value = 1;
		}
		if (*oldlenp < sizeof(value)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &value, sizeof(value));
		*oldlenp = sizeof(value);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_VM && name[1] == VM_LOADAVG) {
		struct loadavg load;
		memset(&load, 0, sizeof(load));
		load.fscale = 2048;
		if (*oldlenp < sizeof(load)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &load, sizeof(load));
		*oldlenp = sizeof(load);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_VM && name[1] == VM_UVMEXP) {
		struct uvmexp exp;
		long pages = sysconf(_SC_PHYS_PAGES);
		long page_size = sysconf(_SC_PAGESIZE);
		memset(&exp, 0, sizeof(exp));
		exp.pagesize = page_size > 0 ? (int)page_size : 4096;
		exp.npages = pages > 0 ? (int)pages : 1024;
		exp.active = exp.npages / 2;
		exp.free = exp.npages / 4;
		if (*oldlenp < sizeof(exp)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &exp, sizeof(exp));
		*oldlenp = sizeof(exp);
		return 0;
	}
	if (namelen == 3 && name[0] == CTL_VFS && name[1] == VFS_GENERIC &&
	    name[2] == VFS_BCACHESTAT) {
		struct bcachestats stats;
		memset(&stats, 0, sizeof(stats));
		if (*oldlenp < sizeof(stats)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &stats, sizeof(stats));
		*oldlenp = sizeof(stats);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN && name[1] == KERN_FSCALE) {
		int fscale = 2048;
		if (*oldlenp < sizeof(fscale)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &fscale, sizeof(fscale));
		*oldlenp = sizeof(fscale);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN && name[1] == KERN_CCPU) {
		unsigned int ccpu = 0;
		if (*oldlenp < sizeof(ccpu)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &ccpu, sizeof(ccpu));
		*oldlenp = sizeof(ccpu);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN && name[1] == KERN_CLOCKRATE) {
		long hz = sysconf(_SC_CLK_TCK);
		struct clockinfo ci;
		if (hz <= 0)
			hz = 100;
		ci.hz = (int)hz;
		ci.tick = (int)(1000000 / hz);
		ci.profhz = (int)hz;
		ci.stathz = (int)hz;
		if (*oldlenp < sizeof(ci)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &ci, sizeof(ci));
		*oldlenp = sizeof(ci);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN &&
	    (name[1] == KERN_MSGBUFSIZE || name[1] == KERN_CONSBUFSIZE)) {
		int msgbufsize = 1;
		if (*oldlenp < sizeof(msgbufsize)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &msgbufsize, sizeof(msgbufsize));
		*oldlenp = sizeof(msgbufsize);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN &&
	    (name[1] == KERN_MSGBUF || name[1] == KERN_CONSBUF)) {
		struct mixtar_kernel_msgbuf *mb = oldp;
		size_t need = offsetof(struct mixtar_kernel_msgbuf, msg_bufc) + 1;
		if (*oldlenp < need) {
			errno = ENOMEM;
			return -1;
		}
		memset(mb, 0, *oldlenp);
		mb->msg_magic = MSG_MAGIC;
		mb->msg_bufx = 0;
		mb->msg_bufr = 0;
		mb->msg_bufs = 1;
		mb->msg_bufc[0] = '\0';
		*oldlenp = need;
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_KERN && name[1] == KERN_CONSDEV) {
		dev_t consdev = 0;
		if (*oldlenp < sizeof(consdev)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &consdev, sizeof(consdev));
		*oldlenp = sizeof(consdev);
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_VM && name[1] == VM_MAXSLP) {
		int maxslp = 20;
		if (*oldlenp < sizeof(maxslp)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &maxslp, sizeof(maxslp));
		*oldlenp = sizeof(maxslp);
		return 0;
	}
	if (namelen == 3 && name[0] == CTL_KERN && name[1] == KERN_PROC_CWD) {
		char path[64];
		ssize_t nread;

		snprintf(path, sizeof(path), "/proc/%d/cwd", name[2]);
		nread = readlink(path, oldp, *oldlenp > 0 ? *oldlenp - 1 : 0);
		if (nread < 0)
			return -1;
		((char *)oldp)[nread] = '\0';
		*oldlenp = (size_t)nread + 1;
		return 0;
	}
	if (namelen == 2 && name[0] == CTL_HW && name[1] == HW_USERMEM64) {
		long pages = sysconf(_SC_PHYS_PAGES);
		long page_size = sysconf(_SC_PAGESIZE);
		unsigned long long memory;
		if (*oldlenp < sizeof(memory)) {
			errno = ENOMEM;
			return -1;
		}
		if (pages <= 0 || page_size <= 0) {
			errno = ENOTSUP;
			return -1;
		}
		memory = (unsigned long long)pages * (unsigned long long)page_size;
		memcpy(oldp, &memory, sizeof(memory));
		*oldlenp = sizeof(memory);
		return 0;
	}
	errno = ENOTSUP;
	return -1;
}

static inline int
sysctlbyname(const char *name, void *oldp, size_t *oldlenp,
    const void *newp, size_t newlen)
{
	(void)newp;
	(void)newlen;
	if (name == NULL || oldp == NULL || oldlenp == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (strcmp(name, "kern.pid_max") == 0) {
		int pid_max = 4194304;
		if (*oldlenp < sizeof(pid_max)) {
			errno = ENOMEM;
			return -1;
		}
		memcpy(oldp, &pid_max, sizeof(pid_max));
		*oldlenp = sizeof(pid_max);
		return 0;
	}
	errno = ENOTSUP;
	return -1;
}

#endif
