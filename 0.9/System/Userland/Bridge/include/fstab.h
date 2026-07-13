/* Mixtar Bridge fstab compatibility shim. */
#ifndef MIXTAR_BRIDGE_FSTAB_H
#define MIXTAR_BRIDGE_FSTAB_H

#define FSTAB_RW "rw"
#define FSTAB_RO "ro"
#define FSTAB_RQ "rq"

#ifndef _PATH_FSTAB
#define _PATH_FSTAB "/etc/fstab"
#endif

struct fstab {
	char *fs_spec;
	char *fs_file;
	char *fs_vfstype;
	char *fs_mntops;
	char *fs_type;
	int fs_freq;
	int fs_passno;
};

static inline struct fstab *
getfsent(void)
{
	return NULL;
}

static inline int
setfsent(void)
{
	return 1;
}

static inline void
endfsent(void)
{
}

static inline struct fstab *
getfsfile(const char *name)
{
	(void)name;
	return NULL;
}

static inline struct fstab *
getfsspec(const char *name)
{
	(void)name;
	return NULL;
}

#endif /* MIXTAR_BRIDGE_FSTAB_H */
