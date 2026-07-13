/* Mixtar Bridge sys/mount compatibility shim. */
#ifndef MIXTAR_BRIDGE_SYS_MOUNT_H
#define MIXTAR_BRIDGE_SYS_MOUNT_H

#include <limits.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <sys/statvfs.h>

#ifndef MFSNAMELEN
#define MFSNAMELEN 16
#endif

#ifndef MNAMELEN
#define MNAMELEN PATH_MAX
#endif

#ifndef MNT_NOWAIT
#define MNT_NOWAIT 1
#endif

#ifndef MNT_WAIT
#define MNT_WAIT 2
#endif

#ifndef MNT_LOCAL
#define MNT_LOCAL 0x00001000
#endif

#ifndef MNT_FORCE
#define MNT_FORCE 0x00080000
#endif

#ifndef MOUNT_NFS
#define MOUNT_NFS "nfs"
#endif

#ifndef MOUNT_MSDOS
#define MOUNT_MSDOS "msdos"
#endif
#ifndef MOUNT_CD9660
#define MOUNT_CD9660 "cd9660"
#endif
#ifndef MOUNT_MFS
#define MOUNT_MFS "mfs"
#endif
#ifndef MOUNT_UFS
#define MOUNT_UFS "ffs"
#endif
#ifndef MOUNT_FFS
#define MOUNT_FFS "ffs"
#endif
#ifndef MOUNT_FUSEFS
#define MOUNT_FUSEFS "fusefs"
#endif
#ifndef MOUNT_TMPFS
#define MOUNT_TMPFS "tmpfs"
#endif

#ifndef VFS_GENERIC
#define VFS_GENERIC 0
#endif
#ifndef VFS_MAXTYPENUM
#define VFS_MAXTYPENUM 1
#endif
#ifndef VFS_CONF
#define VFS_CONF 2
#endif
#ifndef VFS_BCACHESTAT
#define VFS_BCACHESTAT 3
#endif

struct vfsconf {
	char vfc_name[MFSNAMELEN];
	int vfc_typenum;
	unsigned int vfc_refcount;
};

#ifndef MNT_ASYNC
#define MNT_ASYNC 0x00000001
#endif
#ifndef MNT_DEFEXPORTED
#define MNT_DEFEXPORTED 0x00000002
#endif
#ifndef MNT_EXPORTED
#define MNT_EXPORTED 0x00000004
#endif
#ifndef MNT_EXPORTANON
#define MNT_EXPORTANON 0x00000008
#endif
#ifndef MNT_EXRDONLY
#define MNT_EXRDONLY 0x00000010
#endif
#ifndef MNT_NOATIME
#define MNT_NOATIME 0x00000020
#endif
#ifndef MNT_NODEV
#define MNT_NODEV 0x00000040
#endif
#ifndef MNT_NOEXEC
#define MNT_NOEXEC 0x00000080
#endif
#ifndef MNT_NOSUID
#define MNT_NOSUID 0x00000100
#endif
#ifndef MNT_NOPERM
#define MNT_NOPERM 0x00000200
#endif
#ifndef MNT_WXALLOWED
#define MNT_WXALLOWED 0x00000400
#endif
#ifndef MNT_QUOTA
#define MNT_QUOTA 0x00000800
#endif
#ifndef MNT_ROOTFS
#define MNT_ROOTFS 0x00002000
#endif
#ifndef MNT_SYNCHRONOUS
#define MNT_SYNCHRONOUS 0x00004000
#endif
#ifndef MNT_SOFTDEP
#define MNT_SOFTDEP 0x00008000
#endif
#ifndef MNT_UPDATE
#define MNT_UPDATE 0x00010000
#endif
#ifndef MNT_RELOAD
#define MNT_RELOAD 0x00020000
#endif
#ifndef MNT_VISFLAGMASK
#define MNT_VISFLAGMASK (MNT_ASYNC | MNT_EXPORTED | MNT_LOCAL | MNT_NOATIME | \
    MNT_NODEV | MNT_NOEXEC | MNT_NOSUID | MNT_NOPERM | MNT_WXALLOWED | \
    MNT_QUOTA | MNT_RDONLY | MNT_SYNCHRONOUS | MNT_SOFTDEP)
#endif

struct nfs_args {
	int flags;
	int proto;
	int sotype;
	int wsize;
	int rsize;
	int readdirsize;
	int timeo;
	int retrans;
	int maxgrouplist;
	int readahead;
	int acregmin;
	int acregmax;
	int acdirmin;
	int acdirmax;
};

struct msdosfs_args {
	unsigned int uid;
	unsigned int gid;
	unsigned int mask;
	int flags;
};

struct iso_args {
	int flags;
};

struct mfs_args {
	unsigned long size;
};

struct tmpfs_args {
	unsigned int ta_root_uid;
	unsigned int ta_root_gid;
	unsigned int ta_root_mode;
	unsigned long ta_size_max;
	unsigned long ta_nodes_max;
};

struct statfs {
	uint64_t f_flags;
	uint64_t f_bsize;
	uint64_t f_iosize;
	uint64_t f_blocks;
	uint64_t f_bfree;
	uint64_t f_bavail;
	uint64_t f_files;
	uint64_t f_ffree;
	char f_fstypename[MFSNAMELEN];
	char f_mntfromname[PATH_MAX];
	char f_mntfromspec[PATH_MAX];
	char f_mntonname[PATH_MAX];
	time_t f_ctime;
	union {
		struct nfs_args nfs_args;
		struct msdosfs_args msdosfs_args;
		struct iso_args iso_args;
		struct mfs_args mfs_args;
		struct tmpfs_args tmpfs_args;
	} mount_info;
};

static inline void
mixtar_fill_statfs(const char *path, const struct statvfs *vfs,
    struct statfs *buf)
{
	if (buf == 0)
		return;
	memset(buf, 0, sizeof(*buf));
	if (vfs != 0) {
		buf->f_bsize = vfs->f_bsize;
		buf->f_iosize = vfs->f_frsize != 0 ? vfs->f_frsize : vfs->f_bsize;
		buf->f_blocks = vfs->f_blocks;
		buf->f_bfree = vfs->f_bfree;
		buf->f_bavail = vfs->f_bavail;
		buf->f_files = vfs->f_files;
		buf->f_ffree = vfs->f_ffree;
		buf->f_flags = vfs->f_flag;
	}
	snprintf(buf->f_fstypename, sizeof(buf->f_fstypename), "%s", "linux");
	snprintf(buf->f_mntfromname, sizeof(buf->f_mntfromname), "%s", "bridge");
	snprintf(buf->f_mntfromspec, sizeof(buf->f_mntfromspec), "%s", "bridge");
	snprintf(buf->f_mntonname, sizeof(buf->f_mntonname), "%s",
	    path != 0 ? path : "/");
	buf->f_ctime = time(NULL);
}

static inline int
statfs(const char *path, struct statfs *buf)
{
	struct statvfs vfs;

	if (path == 0)
		path = "/";
	if (statvfs(path, &vfs) != 0)
		return -1;
	mixtar_fill_statfs(path, &vfs, buf);
	return 0;
}

static inline int
fstatfs(int fd, struct statfs *buf)
{
	struct statvfs vfs;

	if (fstatvfs(fd, &vfs) != 0)
		return -1;
	mixtar_fill_statfs("/", &vfs, buf);
	return 0;
}

static inline int
getmntinfo(struct statfs **mntbufp, int flags)
{
	static struct statfs rootfs;

	(void)flags;
	if (statfs("/", &rootfs) != 0)
		return 0;
	if (mntbufp != 0)
		*mntbufp = &rootfs;
	return 1;
}

static inline int
unmount(const char *path, int flags)
{
	(void)path;
	(void)flags;
	errno = EPERM;
	return -1;
}

#endif
