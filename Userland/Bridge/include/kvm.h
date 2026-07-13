#ifndef MIXTAR_BRIDGE_KVM_H
#define MIXTAR_BRIDGE_KVM_H

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <nlist.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define KVM_NO_FILES 0x01

#ifndef ARG_MAX
#define ARG_MAX 131072
#endif

typedef struct mixtar_kvm {
	int dummy;
} kvm_t;

static struct kinfo_proc *mixtar_kvm_procs;
static int mixtar_kvm_nprocs;

static inline int
mixtar_proc_is_pid_dir(const char *name)
{
	if (name == NULL || *name == '\0')
		return 0;
	for (const unsigned char *p = (const unsigned char *)name; *p; p++) {
		if (!isdigit(*p))
			return 0;
	}
	return 1;
}

static inline int
mixtar_read_file(const char *path, char *buf, size_t len)
{
	int fd;
	ssize_t n;

	if (buf == NULL || len == 0)
		return -1;
	fd = (open)(path, O_RDONLY | O_CLOEXEC);
	if (fd == -1)
		return -1;
	n = read(fd, buf, len - 1);
	close(fd);
	if (n < 0)
		return -1;
	buf[n] = '\0';
	return 0;
}

static inline void
mixtar_proc_read_status(struct kinfo_proc *kp, pid_t pid)
{
	char path[64];
	char buf[4096];
	char *line;

	snprintf(path, sizeof(path), "/proc/%ld/status", (long)pid);
	if (mixtar_read_file(path, buf, sizeof(buf)) != 0)
		return;

	line = strtok(buf, "\n");
	while (line != NULL) {
		unsigned int a = 0, b = 0, c = 0, d = 0;
		if (sscanf(line, "Uid:\t%u\t%u\t%u\t%u", &a, &b, &c, &d) == 4) {
			kp->p_ruid = (uid_t)a;
			kp->p_uid = (uid_t)b;
			kp->p_svuid = (uid_t)c;
		} else if (sscanf(line, "Gid:\t%u\t%u\t%u\t%u", &a, &b, &c, &d) == 4) {
			kp->p_rgid = (gid_t)a;
			kp->p_gid = (gid_t)b;
			kp->p_svgid = (gid_t)c;
		}
		line = strtok(NULL, "\n");
	}
}

static inline int
mixtar_proc_state(char state)
{
	switch (state) {
	case 'R':
		return SRUN;
	case 'S':
	case 'D':
	case 'I':
		return SSLEEP;
	case 'T':
	case 't':
		return SSTOP;
	case 'Z':
		return SZOMB;
	case 'X':
		return SDEAD;
	default:
		return SRUN;
	}
}

static inline int
mixtar_proc_load_stat(struct kinfo_proc *kp, pid_t pid)
{
	char path[64];
	char buf[4096];
	char *openp;
	char *closep;
	char state = 'R';
	long ppid = 0, pgrp = 0, session = 0, tty_nr = 0, tpgid = 0;
	long flags = 0, minflt = 0, cminflt = 0, majflt = 0, cmajflt = 0;
	unsigned long utime = 0, stime = 0, cutime = 0, cstime = 0;
	long priority = 0, nicev = 0, num_threads = 0, itrealvalue = 0;
	unsigned long long starttime = 0;
	unsigned long vsize = 0;
	long rss = 0;
	const char *rest;
	long hz;
	long page_size;

	snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
	if (mixtar_read_file(path, buf, sizeof(buf)) != 0)
		return -1;

	openp = strchr(buf, '(');
	closep = strrchr(buf, ')');
	if (openp == NULL || closep == NULL || closep <= openp)
		return -1;

	*closep = '\0';
	snprintf(kp->p_comm, sizeof(kp->p_comm), "%s", openp + 1);
	snprintf(kp->p_name, sizeof(kp->p_name), "%s", openp + 1);
	rest = closep + 2;

	if (sscanf(rest, "%c %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld %lu %lu %lu %lu %ld %ld %ld %ld %llu %lu %ld",
	    &state, &ppid, &pgrp, &session, &tty_nr, &tpgid, &flags,
	    &minflt, &cminflt, &majflt, &cmajflt, &utime, &stime, &cutime,
	    &cstime, &priority, &nicev, &num_threads, &itrealvalue,
	    &starttime, &vsize, &rss) < 22)
		return -1;

	hz = sysconf(_SC_CLK_TCK);
	page_size = sysconf(_SC_PAGESIZE);
	if (hz <= 0)
		hz = 100;
	if (page_size <= 0)
		page_size = 4096;

	kp->p_pid = pid;
	kp->p_tid = pid;
	kp->p_ppid = (pid_t)ppid;
	kp->p__pgid = (pid_t)pgrp;
	kp->p_sid = (pid_t)session;
	kp->p_tdev = (dev_t)tty_nr;
	kp->p_tpgid = (pid_t)tpgid;
	kp->p_psflags = tty_nr != 0 ? PS_CONTROLT : 0;
	kp->p_flag = (uint32_t)flags;
	kp->p_stat = mixtar_proc_state(state);
	kp->p_priority = (int)priority;
	kp->p_nice = (int)nicev;
	kp->p_vm_rssize = rss > 0 ? (unsigned long)rss : 0;
	kp->p_rssize = kp->p_vm_rssize;
	kp->p_vm_tsize = vsize / (unsigned long)page_size;
	kp->p_vm_dsize = 0;
	kp->p_vm_ssize = 0;
	kp->p_uru_minflt = (unsigned long)minflt;
	kp->p_uru_majflt = (unsigned long)majflt;
	kp->p_rtime_sec = (unsigned int)((utime + stime) / (unsigned long)hz);
	kp->p_rtime_usec = (unsigned int)(((utime + stime) % (unsigned long)hz) * (1000000 / hz));
	kp->p_uctime_sec = (unsigned int)(utime / (unsigned long)hz);
	kp->p_uctime_usec = (unsigned int)((utime % (unsigned long)hz) * (1000000 / hz));
	kp->p_ustart_sec = (unsigned int)(starttime / (unsigned long long)hz);
	kp->p_ustart_usec = (unsigned int)((starttime % (unsigned long long)hz) * (1000000 / hz));
	kp->p_uvalid = 1;
	snprintf(kp->p_wmesg, sizeof(kp->p_wmesg), "-");
	mixtar_proc_read_status(kp, pid);
	return 0;
}

static inline kvm_t *
kvm_openfiles(const char *execfile, const char *corefile, const char *swapfile,
    int flags, char *errbuf)
{
	static kvm_t kd;

	(void)execfile;
	(void)corefile;
	(void)swapfile;
	(void)flags;
	if (errbuf != NULL)
		errbuf[0] = '\0';
	return &kd;
}

static inline kvm_t *
kvm_open(const char *execfile, const char *corefile, const char *swapfile,
    int flags, const char *errstr)
{
	char *errbuf = (char *)errstr;

	return kvm_openfiles(execfile, corefile, swapfile, flags, errbuf);
}

static inline const char *
kvm_geterr(kvm_t *kd)
{
	(void)kd;
	return "Linux /proc bridge";
}

static inline int
kvm_nlist(kvm_t *kd, struct nlist *nl)
{
	int i;

	(void)kd;
	if (nl == NULL)
		return 0;
	for (i = 0; nl[i].n_name != NULL; i++)
		nl[i].n_value = (unsigned long)(i + 1);
	return 0;
}

static inline ssize_t
kvm_read(kvm_t *kd, unsigned long addr, void *buf, size_t len)
{
	(void)kd;
	(void)addr;
	if (buf == NULL) {
		errno = EINVAL;
		return -1;
	}
	memset(buf, 0, len);
	return (ssize_t)len;
}

static inline struct kinfo_proc *
kvm_getprocs(kvm_t *kd, int op, int arg, size_t esize, int *cnt)
{
	DIR *dir;
	struct dirent *de;
	int cap = 0;

	(void)kd;
	(void)esize;
	free(mixtar_kvm_procs);
	mixtar_kvm_procs = NULL;
	mixtar_kvm_nprocs = 0;

	dir = opendir("/proc");
	if (dir == NULL)
		return NULL;
	while ((de = readdir(dir)) != NULL) {
		pid_t pid;
		struct kinfo_proc kp;

		if (!mixtar_proc_is_pid_dir(de->d_name))
			continue;
		pid = (pid_t)strtol(de->d_name, NULL, 10);
		memset(&kp, 0, sizeof(kp));
		if (mixtar_proc_load_stat(&kp, pid) != 0)
			continue;
		if (op == KERN_PROC_PID && kp.p_pid != (pid_t)arg)
			continue;
		if (op == KERN_PROC_UID && kp.p_uid != (uid_t)arg)
			continue;
		if (op == KERN_PROC_TTY && kp.p_tdev != (dev_t)arg)
			continue;
		if (mixtar_kvm_nprocs == cap) {
			int next = cap == 0 ? 64 : cap * 2;
			struct kinfo_proc *grown = realloc(mixtar_kvm_procs,
			    (size_t)next * sizeof(*grown));
			if (grown == NULL) {
				closedir(dir);
				return NULL;
			}
			mixtar_kvm_procs = grown;
			cap = next;
		}
		mixtar_kvm_procs[mixtar_kvm_nprocs++] = kp;
	}
	closedir(dir);
	if (cnt != NULL)
		*cnt = mixtar_kvm_nprocs;
	return mixtar_kvm_procs;
}

static inline char **
kvm_getargv(kvm_t *kd, const struct kinfo_proc *kp, int nchr)
{
	static char buf[ARG_MAX];
	static char *argv[256];
	char path[64];
	ssize_t n;
	int fd;
	size_t i;
	int argc = 0;

	(void)kd;
	(void)nchr;
	if (kp == NULL)
		return NULL;
	snprintf(path, sizeof(path), "/proc/%ld/cmdline", (long)kp->p_pid);
	fd = (open)(path, O_RDONLY | O_CLOEXEC);
	if (fd == -1)
		return NULL;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0) {
		argv[0] = (char *)kp->p_comm;
		argv[1] = NULL;
		return argv;
	}
	buf[n] = '\0';
	for (i = 0; i < (size_t)n && argc < 255; ) {
		argv[argc++] = &buf[i];
		while (i < (size_t)n && buf[i] != '\0')
			i++;
		while (i < (size_t)n && buf[i] == '\0')
			i++;
	}
	argv[argc] = NULL;
	return argv;
}

static inline char **
kvm_getenvv(kvm_t *kd, const struct kinfo_proc *kp, int nchr)
{
	(void)kd;
	(void)kp;
	(void)nchr;
	return NULL;
}

static inline int
kvm_close(kvm_t *kd)
{
	(void)kd;
	return 0;
}

#endif
