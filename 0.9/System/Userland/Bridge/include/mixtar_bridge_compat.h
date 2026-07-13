/* Mixtar Bridge forced-include compatibility header.
 *
 * This file is injected with `-include` so the Bridge does not shadow libc
 * headers. Keep upstream FreeBSD source untouched.
 */
#ifndef MIXTAR_BRIDGE_COMPAT_H
#define MIXTAR_BRIDGE_COMPAT_H

#ifdef MIXTAR_BRIDGE

#ifndef __dead2
#define __dead2 __attribute__((__noreturn__))
#endif

#ifndef __dead
#define __dead __attribute__((__noreturn__))
#endif

#ifndef __pure
#define __pure __attribute__((__pure__))
#endif

#ifndef __unreachable
#define __unreachable() __builtin_unreachable()
#endif

#ifndef __printf0like
#define __printf0like(fmtarg, firstvararg) __attribute__((__format__(__printf__, fmtarg, firstvararg)))
#endif

#ifndef __printf_like
#define __printf_like(fmtarg, firstvararg) __attribute__((__format__(__printf__, fmtarg, firstvararg)))
#endif

#ifndef __printflike
#define __printflike(fmtarg, firstvararg) __attribute__((__format__(__printf__, fmtarg, firstvararg)))
#endif

#ifndef __aligned
#define __aligned(x) __attribute__((__aligned__(x)))
#endif

#ifndef __nonstring
#define __nonstring
#endif

#include <errno.h>
#include <err.h>
#include <fcntl.h>
#include <fts.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <regex.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <termios.h>
#include <wchar.h>
#include <sys/file.h>
#include <sys/types.h>
#ifdef __linux__
#include <arpa/inet.h>
#include <endian.h>
#include <elf.h>
#include <pty.h>
#include <stdio_ext.h>
#include <sys/ipc.h>
#define msgbuf mixtar_linux_msgbuf
#include <sys/msg.h>
#undef msgbuf
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/sysmacros.h>
#endif
#include <sys/stat.h>
#include <sys/proc.h>
#include <time.h>
#include <unistd.h>

#ifndef __DECONST
#define __DECONST(type, var) ((type)(uintptr_t)(const void *)(var))
#endif

#if defined(__linux__) && !defined(HAVE_FUNOPEN)
#ifndef MIXTAR_BRIDGE_FUNOPEN_DEFINED
#define MIXTAR_BRIDGE_FUNOPEN_DEFINED
typedef int (*mixtar_funopen_readfn)(void *, char *, int);
typedef int (*mixtar_funopen_writefn)(void *, const char *, int);
typedef off_t (*mixtar_funopen_seekfn)(void *, off_t, int);
typedef int (*mixtar_funopen_closefn)(void *);

struct mixtar_funopen_cookie {
	void *cookie;
	mixtar_funopen_readfn readfn;
	mixtar_funopen_writefn writefn;
	mixtar_funopen_seekfn seekfn;
	mixtar_funopen_closefn closefn;
};

#if defined(__GLIBC__)
typedef off64_t mixtar_fopencookie_off_t;
#else
typedef off_t mixtar_fopencookie_off_t;
#endif

static ssize_t
mixtar_funopen_read(void *opaque, char *buf, size_t size)
{
	struct mixtar_funopen_cookie *state;
	int want;

	state = (struct mixtar_funopen_cookie *)opaque;
	if (state == NULL || state->readfn == NULL) {
		errno = EBADF;
		return -1;
	}
	want = size > (size_t)INT_MAX ? INT_MAX : (int)size;
	return state->readfn(state->cookie, buf, want);
}

static ssize_t
mixtar_funopen_write(void *opaque, const char *buf, size_t size)
{
	struct mixtar_funopen_cookie *state;
	int want;

	state = (struct mixtar_funopen_cookie *)opaque;
	if (state == NULL || state->writefn == NULL) {
		errno = EBADF;
		return -1;
	}
	want = size > (size_t)INT_MAX ? INT_MAX : (int)size;
	return state->writefn(state->cookie, buf, want);
}

static int
mixtar_funopen_seek(void *opaque, mixtar_fopencookie_off_t *offset, int whence)
{
	struct mixtar_funopen_cookie *state;
	off_t next;

	state = (struct mixtar_funopen_cookie *)opaque;
	if (state == NULL || state->seekfn == NULL) {
		errno = ESPIPE;
		return -1;
	}
	next = state->seekfn(state->cookie, (off_t)*offset, whence);
	if (next < 0)
		return -1;
	*offset = (mixtar_fopencookie_off_t)next;
	return 0;
}

static int
mixtar_funopen_close(void *opaque)
{
	struct mixtar_funopen_cookie *state;
	int rc;

	state = (struct mixtar_funopen_cookie *)opaque;
	if (state == NULL)
		return 0;
	rc = state->closefn == NULL ? 0 : state->closefn(state->cookie);
	free(state);
	return rc;
}

static inline FILE *
funopen(void *cookie, mixtar_funopen_readfn readfn,
    mixtar_funopen_writefn writefn, mixtar_funopen_seekfn seekfn,
    mixtar_funopen_closefn closefn)
{
	struct mixtar_funopen_cookie *state;
	cookie_io_functions_t io;
	FILE *fp;

	state = calloc(1, sizeof(*state));
	if (state == NULL)
		return NULL;
	state->cookie = cookie;
	state->readfn = readfn;
	state->writefn = writefn;
	state->seekfn = seekfn;
	state->closefn = closefn;
	memset(&io, 0, sizeof(io));
	if (readfn != NULL)
		io.read = mixtar_funopen_read;
	if (writefn != NULL)
		io.write = mixtar_funopen_write;
	if (seekfn != NULL)
		io.seek = mixtar_funopen_seek;
	io.close = mixtar_funopen_close;
	fp = fopencookie(state, readfn != NULL ? "r+" : "w", io);
	if (fp == NULL)
		free(state);
	return fp;
}

static inline FILE *
fwopen(void *cookie, mixtar_funopen_writefn writefn)
{
	return funopen(cookie, NULL, writefn, NULL, NULL);
}
#endif
#endif

#if defined(__linux__) && !defined(HAVE_TCSETSID)
static inline int
tcsetsid(int fd, pid_t pid)
{
	(void)fd;
	(void)pid;
	return 0;
}
#endif

#if defined(__linux__) && !defined(__GLIBC__)
static inline void
closefrom(int lowfd)
{
	long maxfd;
	int fd;

	maxfd = sysconf(_SC_OPEN_MAX);
	if (maxfd < 0)
		maxfd = 1024;
	for (fd = lowfd; fd < maxfd; fd++)
		(void)close(fd);
}
#endif

#ifndef __unused
#define __unused __attribute__((__unused__))
#endif

#ifndef NODEV
#define NODEV ((dev_t)-1)
#endif

#ifndef ALLPERMS
#define ALLPERMS 07777
#endif

#ifndef ACCESSPERMS
#define ACCESSPERMS 0777
#endif

#ifndef DEFFILEMODE
#define DEFFILEMODE 0666
#endif

#ifndef _PATH_DEVDB
#define _PATH_DEVDB "/dev"
#endif

#ifndef _PATH_CSHELL
#define _PATH_CSHELL "/System/Tools/MixtarRVS/bin/csh"
#endif

#ifndef MAXNAMLEN
#define MAXNAMLEN 255
#endif

#ifndef REG_STARTEND
#define REG_STARTEND 0x08000000
#define MIXTAR_BRIDGE_EMULATE_REG_STARTEND 1
#endif

#ifndef O_VERIFY
#define O_VERIFY 0
#endif

#ifndef CLOCK_UPTIME
#define CLOCK_UPTIME CLOCK_MONOTONIC
#endif

#ifndef MAXLOGNAME
#define MAXLOGNAME 33
#endif

#ifndef ALIGN
#define ALIGN(n) (((n) + sizeof(max_align_t) - 1) & ~(sizeof(max_align_t) - 1))
#endif

#ifndef TIOCSTAT
#define TIOCSTAT 0
#endif

#ifndef CCEQ
#define CCEQ(val, c) ((val) == (c))
#endif

#if defined(__linux__) && !defined(__GLIBC__)
#ifndef c_ispeed
#define c_ispeed __c_ispeed
#endif
#ifndef c_ospeed
#define c_ospeed __c_ospeed
#endif
#endif

#ifndef CTRL
#define CTRL(x) ((x) & 037)
#endif

#ifndef CDISCARD
#define CDISCARD CTRL('o')
#endif
#ifndef CDSUSP
#define CDSUSP CTRL('y')
#endif
#ifndef CEOF
#define CEOF CTRL('d')
#endif
#ifndef CEOL
#define CEOL 0
#endif
#ifndef CERASE
#define CERASE 0177
#endif
#ifndef CINTR
#define CINTR CTRL('c')
#endif
#ifndef CKILL
#define CKILL CTRL('u')
#endif
#ifndef CLNEXT
#define CLNEXT CTRL('v')
#endif
#ifndef CMIN
#define CMIN 1
#endif
#ifndef CQUIT
#define CQUIT 034
#endif
#ifndef CREPRINT
#define CREPRINT CTRL('r')
#endif
#ifndef CSTART
#define CSTART CTRL('q')
#endif
#ifndef CSTATUS
#define CSTATUS CTRL('t')
#endif
#ifndef CSTOP
#define CSTOP CTRL('s')
#endif
#ifndef CSUSP
#define CSUSP CTRL('z')
#endif
#ifndef CTIME
#define CTIME 0
#endif
#ifndef CWERASE
#define CWERASE CTRL('w')
#endif

#ifdef MIXTAR_SH_COMPAT
#ifdef CEOF
#undef CEOF
#endif
#endif

#ifndef SIG2STR_MAX
#define SIG2STR_MAX 32
#endif

#ifndef sys_nsig
#define sys_nsig NSIG
#endif

#if defined(__linux__) && !defined(HAVE_SIG2STR)
static inline int
sig2str(int sig, char *str)
{
	if (sig <= 0 || sig >= NSIG) {
		errno = EINVAL;
		return -1;
	}
	snprintf(str, SIG2STR_MAX, "%d", sig);
	return 0;
}

static inline int
str2sig(const char *name, int *sig)
{
	char *end;
	long value;

	if (name == NULL || sig == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (strncasecmp(name, "SIG", 3) == 0)
		name += 3;
	if (strcasecmp(name, "HUP") == 0) {
		*sig = SIGHUP;
		return 0;
	}
	if (strcasecmp(name, "INT") == 0) {
		*sig = SIGINT;
		return 0;
	}
	if (strcasecmp(name, "KILL") == 0) {
		*sig = SIGKILL;
		return 0;
	}
	if (strcasecmp(name, "TERM") == 0) {
		*sig = SIGTERM;
		return 0;
	}
	value = strtol(name, &end, 10);
	if (*name != '\0' && *end == '\0' && value > 0 && value < NSIG) {
		*sig = (int)value;
		return 0;
	}
	errno = EINVAL;
	return -1;
}
#endif

#ifndef TTYDEF_CFLAG
#define TTYDEF_CFLAG (CREAD | CS8 | HUPCL)
#endif
#ifndef TTYDEF_IFLAG
#define TTYDEF_IFLAG (BRKINT | ICRNL | IXON)
#endif
#ifndef TTYDEF_LFLAG
#define TTYDEF_LFLAG (ECHO | ICANON | ISIG | IEXTEN)
#endif
#ifndef TTYDEF_OFLAG
#define TTYDEF_OFLAG (OPOST | ONLCR)
#endif

#if defined(__linux__) && !defined(__GLIBC__)
struct rpcent {
	char *r_name;
	char **r_aliases;
	int r_number;
};

static inline void
setrpcent(int stayopen)
{
	(void)stayopen;
}

static inline void
endrpcent(void)
{
}

static inline struct rpcent *
getrpcent(void)
{
	return NULL;
}

static inline struct rpcent *
getrpcbyname(const char *name)
{
	(void)name;
	return NULL;
}

static inline struct rpcent *
getrpcbynumber(int number)
{
	(void)number;
	return NULL;
}
#endif

size_t strlcpy(char *dst, const char *src, size_t dstsize);
size_t strlcat(char *dst, const char *src, size_t dstsize);
int setlogin(const char *name);
int revoke(const char *path);
int issetugid(void);
void logwtmp(const char *line, const char *name, const char *host);
int isduid(const char *value, int flags);
int getrtable(void);
int setpassent(int stayopen);
int setgroupent(int stayopen);
int chflags(const char *path, unsigned long flags);
int lchflags(const char *path, unsigned long flags);
int fchflags(int fd, unsigned long flags);
int chflagsat(int fd, const char *path, unsigned long flags, int atflags);
long lpathconf(const char *path, int name);
int undelete(const char *path);
void strmode(mode_t mode, char *p);
char *getbsize(int *headerlen, long *blocksize);
void *setmode(const char *mode_text);
mode_t getmode(const void *set, mode_t base);
long long strtonum(const char *nptr, long long minval, long long maxval, const char **errstr);
char *fflagstostr(unsigned long flags);
int strtofflags(char **stringp, unsigned int *setp, unsigned int *clrp);

#if defined(__linux__) && !defined(__GLIBC__)
#ifndef strtoq
#define strtoq(nptr, endptr, base) strtoll((nptr), (endptr), (base))
#endif
#endif

#ifdef MIXTAR_CHFLAGS_COMPAT
static inline int
mixtar_bridge_chflags_strtofflags(char **stringp, unsigned long *setp, unsigned long *clrp)
{
	unsigned int set32 = 0;
	unsigned int clr32 = 0;
	int rc = strtofflags(stringp, &set32, &clr32);
	if (setp != NULL)
		*setp = (unsigned long)set32;
	if (clrp != NULL)
		*clrp = (unsigned long)clr32;
	return rc;
}
#define strtofflags mixtar_bridge_chflags_strtofflags
#endif
void *recallocarray(void *ptr, size_t oldnmemb, size_t nmemb, size_t size);
void freezero(void *ptr, size_t size);
#define MIXTAR_BRIDGE_HAS_GETBSIZE 1

#ifndef __BEGIN_DECLS
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#endif

#ifndef __bounded__
#define __bounded__(a, b, c)
#endif

#ifndef DEF_WEAK
#define DEF_WEAK(name) extern int __mixtar_bridge_def_weak_##name
#endif

#if defined(__linux__) && !defined(BYTE_ORDER) && defined(__BYTE_ORDER)
#define BYTE_ORDER __BYTE_ORDER
#endif

#if defined(__linux__) && !defined(LITTLE_ENDIAN) && defined(__LITTLE_ENDIAN)
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#endif

#if defined(__linux__) && !defined(BIG_ENDIAN) && defined(__BIG_ENDIAN)
#define BIG_ENDIAN __BIG_ENDIAN
#endif

#if defined(__linux__)
int login_tty(int fd);
#endif

#if defined(__GLIBC__) && !defined(__progname)
#define __progname program_invocation_short_name
#endif

#ifndef SIGINFO
#define SIGINFO SIGUSR1
#endif

#ifndef IPPORT_HILASTAUTO
#define IPPORT_HILASTAUTO 65535
#endif

#if defined(MIXTAR_NM_COMPAT)
#ifndef N_COMM
#define N_COMM 0x12
#endif

#ifndef N_SIZE
#define N_SIZE 0x14
#endif

#ifndef RANLIBMAG
#define RANLIBMAG "__.SYMDEF"
#endif

#ifndef IS_ELF
#define IS_ELF(ehdr) ((ehdr).e_ident[EI_MAG0] == ELFMAG0 && \
    (ehdr).e_ident[EI_MAG1] == ELFMAG1 && \
    (ehdr).e_ident[EI_MAG2] == ELFMAG2 && \
    (ehdr).e_ident[EI_MAG3] == ELFMAG3)
#endif
#endif

static inline uint16_t
mixtar_swap16(uint16_t x)
{
	return (uint16_t)((x >> 8) | (x << 8));
}

static inline uint32_t
mixtar_swap32(uint32_t x)
{
	return __builtin_bswap32(x);
}

static inline uint64_t
mixtar_swap64(uint64_t x)
{
	return __builtin_bswap64(x);
}

#ifndef swap16
#define swap16 mixtar_swap16
#endif
#ifndef swap32
#define swap32 mixtar_swap32
#endif
#ifndef swap64
#define swap64 mixtar_swap64
#endif

#ifndef _PATH_UNIX
#define _PATH_UNIX "/boot/vmlinuz"
#endif

#ifndef betoh32
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define betoh32(x) (x)
#else
#define betoh32(x) __builtin_bswap32(x)
#endif
#endif

#if defined(__linux__) && defined(MIXTAR_BRIDGE_W_COMPAT)
#ifndef sa_len
#define sa_len sa_family
#endif
#endif

#if defined(__linux__) && defined(MIXTAR_BRIDGE_GPROF_COMPAT)
typedef Elf64_Ehdr Elf_Ehdr;
typedef Elf64_Shdr Elf_Shdr;
typedef Elf64_Sym Elf_Sym;
#ifndef ELF_ST_BIND
#define ELF_ST_BIND ELF64_ST_BIND
#endif
#ifndef ELF_ST_TYPE
#define ELF_ST_TYPE ELF64_ST_TYPE
#endif
#ifndef IS_ELF
#define IS_ELF(eh) ((eh).e_ident[EI_MAG0] == ELFMAG0 && \
    (eh).e_ident[EI_MAG1] == ELFMAG1 && \
    (eh).e_ident[EI_MAG2] == ELFMAG2 && \
    (eh).e_ident[EI_MAG3] == ELFMAG3)
#endif
#endif

#if defined(__linux__) && defined(MIXTAR_BRIDGE_SYSV_IPC)
struct semid_ds;
struct seminfo;
union semun {
	int val;
	struct semid_ds *buf;
	unsigned short *array;
	struct seminfo *__buf;
};
#endif

/*
 * OpenBSD stty exposes several line-discipline controls that Linux either
 * names differently or does not support.  Keep unsupported flags inert so
 * ordinary Linux terminal state still compiles and behaves normally.
 */
#ifndef VDSUSP
#define VDSUSP 17
#endif
#ifndef VSTATUS
#define VSTATUS 18
#endif
#ifndef TIOCEXT
#define TIOCEXT 0
#endif
#ifndef TIOCSTART
#define TIOCSTART 0
#endif
#ifndef TIOCSTOP
#define TIOCSTOP 0
#endif
#ifndef TTYDISC
#define TTYDISC 0
#endif
#ifndef PPPDISC
#define PPPDISC 1
#endif
#ifndef NMEADISC
#define NMEADISC 2
#endif
#ifndef ALTWERASE
#define ALTWERASE 0
#endif
#ifndef NOKERNINFO
#define NOKERNINFO 0
#endif
#ifndef MDMBUF
#define MDMBUF 0
#endif
#ifndef OXTABS
#ifdef XTABS
#define OXTABS XTABS
#else
#define OXTABS 0
#endif
#endif
#ifndef ONOEOT
#define ONOEOT 0
#endif

#ifndef MACHINE
#define MACHINE "amd64"
#endif

#ifndef MACHINE_ARCH
#define MACHINE_ARCH "amd64"
#endif

#ifndef UID_MAX
#define UID_MAX UINT_MAX
#endif

#ifndef GID_MAX
#define GID_MAX UINT_MAX
#endif

#ifndef QUAD_MAX
#define QUAD_MAX LLONG_MAX
#endif

#ifndef _PATH_DEFTAPE
#define _PATH_DEFTAPE "/dev/nst0"
#endif

#ifndef nitems
#define nitems(x) (sizeof((x)) / sizeof((x)[0]))
#endif

#ifndef howmany
#define howmany(x, y) (((x) + ((y) - 1)) / (y))
#endif

#ifndef O_SEARCH
#define O_SEARCH O_RDONLY
#endif

#ifndef AT_RESOLVE_BENEATH
#define AT_RESOLVE_BENEATH 0
#endif

#ifndef O_RESOLVE_BENEATH
#define O_RESOLVE_BENEATH 0
#endif

#ifndef S_IFWHT
#define S_IFWHT 0
#endif

#ifndef S_ISWHT
#define S_ISWHT(mode) (0)
#endif

#ifndef S_ISTXT
#define S_ISTXT S_ISVTX
#endif

#ifndef EFTYPE
#define EFTYPE ENOEXEC
#endif

#ifndef REG_BASIC
#define REG_BASIC 0
#endif

#ifndef REG_NOSPEC
#define REG_NOSPEC 0
#endif

#ifndef optreset
#define optreset optind
#endif

#if defined(__linux__)
#if defined(MIXTAR_BRIDGE_W_COMPAT)
#define MIXTAR_BRIDGE_DEFAULT_UTMP "/dev/null"
#else
#define MIXTAR_BRIDGE_DEFAULT_UTMP "/var/run/utmp"
#endif
static inline const char *
mixtar_bridge_utmp_path(void)
{
	const char *path = getenv("MIXTAR_UTMP_PATH");
	if (path != NULL && *path != '\0')
		return path;
	return MIXTAR_BRIDGE_DEFAULT_UTMP;
}
#undef _PATH_UTMP
#define _PATH_UTMP mixtar_bridge_utmp_path()
#endif

#ifndef UF_APPEND
#define UF_APPEND 0
#endif
#ifndef UF_IMMUTABLE
#define UF_IMMUTABLE 0
#endif
#ifndef SF_APPEND
#define SF_APPEND 0
#endif
#ifndef SF_IMMUTABLE
#define SF_IMMUTABLE 0
#endif
#ifndef UF_ARCHIVE
#define UF_ARCHIVE 0
#endif
#ifndef UF_NODUMP
#define UF_NODUMP 0
#endif
#ifndef UF_OPAQUE
#define UF_OPAQUE 0
#endif
#ifndef SF_ARCHIVED
#define SF_ARCHIVED 0
#endif
#ifndef MNT_RDONLY
#define MNT_RDONLY ST_RDONLY
#endif
#ifndef FTS_MAXLEVEL
#define FTS_MAXLEVEL INT_MAX
#endif

#ifndef _PC_ACL_NFS4
#define _PC_ACL_NFS4 20001
#endif

#ifndef _PC_ACL_EXTENDED
#define _PC_ACL_EXTENDED 20002
#endif

/*
 * OpenBSD getconf exposes a few POSIX/XSI constants that glibc may omit.
 * Use negative IDs for runtime-query constants so sysconf/pathconf/confstr
 * reports them as unsupported instead of colliding with Linux-defined values.
 */
#ifndef _SC_XOPEN_UUCP
#define _SC_XOPEN_UUCP -20001
#endif

#ifndef _XOPEN_NAME_MAX
#define _XOPEN_NAME_MAX 255
#endif

#ifndef _XOPEN_PATH_MAX
#define _XOPEN_PATH_MAX 1024
#endif

#ifndef _PC_TIMESTAMP_RESOLUTION
#define _PC_TIMESTAMP_RESOLUTION -20002
#endif

#ifndef _CS_POSIX_V7_THREADS_CFLAGS
#define _CS_POSIX_V7_THREADS_CFLAGS -20003
#endif

#ifndef _CS_POSIX_V7_THREADS_LDFLAGS
#define _CS_POSIX_V7_THREADS_LDFLAGS -20004
#endif

#ifndef _PATH_CP
#define _PATH_CP "/bin/cp"
#endif
#ifndef _PATH_RM
#define _PATH_RM "/bin/rm"
#endif

/*
 * Linux stat lacks FreeBSD birthtime and file flags.  For strict-compile
 * probing we map birthtime sorting to mtime and make file flags read as zero.
 */
#ifndef st_birthtim
#define st_birthtim st_mtim
#endif
#ifndef st_birthtime
#define st_birthtime st_mtime
#endif
#ifndef __st_birthtim
#define __st_birthtim st_mtim
#endif
#ifndef __st_birthtime
#define __st_birthtime st_mtime
#endif
#ifndef st_flags
#define st_flags st_mode
#endif
#ifndef st_gen
#define st_gen st_ino
#endif

#ifndef D_MD_ORDER
#define D_MD_ORDER 0
#endif

#ifndef _PASSWORD_LEN
#define _PASSWORD_LEN 128
#endif

/*
 * glibc exposes NL_TEXTMAX as INT_MAX.  OpenBSD tools use it as a small
 * stack-buffer bound for diagnostic text, so keep the bridge value finite.
 */
#if defined(NL_TEXTMAX) && NL_TEXTMAX > 65536
#undef NL_TEXTMAX
#define NL_TEXTMAX 2048
#elif !defined(NL_TEXTMAX)
#define NL_TEXTMAX 2048
#endif

#ifndef __predict_false
#define __predict_false(x) (x)
#endif

#ifndef MAXPHYS
#define MAXPHYS (128 * 1024)
#endif

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

#define fts_open(paths, options, compar) \
	fts_open((paths), (options), (int (*)(const FTSENT **, const FTSENT **))(compar))

#define MIXTAR_BRIDGE_UNVEIL_MAX 64

enum mixtar_bridge_pledge_bits {
	MIXTAR_PLEDGE_STDIO = 1 << 0,
	MIXTAR_PLEDGE_RPATH = 1 << 1,
	MIXTAR_PLEDGE_WPATH = 1 << 2,
	MIXTAR_PLEDGE_CPATH = 1 << 3,
	MIXTAR_PLEDGE_TMPPATH = 1 << 4,
	MIXTAR_PLEDGE_INET = 1 << 5,
	MIXTAR_PLEDGE_DNS = 1 << 6,
	MIXTAR_PLEDGE_PROC = 1 << 7,
	MIXTAR_PLEDGE_EXEC = 1 << 8,
};

struct mixtar_bridge_unveil_rule {
	char path[PATH_MAX];
	int perms;
};

static int mixtar_bridge_pledge_active;
static unsigned int mixtar_bridge_pledge_mask;
static int mixtar_bridge_unveil_count;
static int mixtar_bridge_unveil_locked;
static struct mixtar_bridge_unveil_rule
    mixtar_bridge_unveil_rules[MIXTAR_BRIDGE_UNVEIL_MAX];

static const char *const sys_signame[] = {
	"0", "hup", "int", "quit", "ill", "trap", "abrt", "bus",
	"fpe", "kill", "usr1", "segv", "usr2", "pipe", "alrm", "term",
	"stkflt", "chld", "cont", "stop", "tstp", "ttin", "ttou", "urg",
	"xcpu", "xfsz", "vtalrm", "prof", "winch", "io", "pwr", "sys",
	"rt32", "rt33", "rt34", "rt35", "rt36", "rt37", "rt38", "rt39",
	"rt40", "rt41", "rt42", "rt43", "rt44", "rt45", "rt46", "rt47",
	"rt48", "rt49", "rt50", "rt51", "rt52", "rt53", "rt54", "rt55",
	"rt56", "rt57", "rt58", "rt59", "rt60", "rt61", "rt62", "rt63",
	"rt64"
};

static const char *const sys_siglist[] = {
	"Signal 0", "Hangup", "Interrupt", "Quit", "Illegal instruction",
	"Trace/breakpoint trap", "Abort", "Bus error",
	"Floating point exception", "Killed", "User defined signal 1",
	"Segmentation fault", "User defined signal 2", "Broken pipe",
	"Alarm clock", "Terminated", "Stack fault", "Child exited",
	"Continued", "Stopped", "Stopped", "Stopped", "Stopped",
	"Urgent I/O condition", "CPU time limit exceeded",
	"File size limit exceeded", "Virtual timer expired",
	"Profiling timer expired", "Window changed", "I/O possible",
	"Power failure", "Bad system call", "Realtime signal 32",
	"Realtime signal 33", "Realtime signal 34", "Realtime signal 35",
	"Realtime signal 36", "Realtime signal 37", "Realtime signal 38",
	"Realtime signal 39", "Realtime signal 40", "Realtime signal 41",
	"Realtime signal 42", "Realtime signal 43", "Realtime signal 44",
	"Realtime signal 45", "Realtime signal 46", "Realtime signal 47",
	"Realtime signal 48", "Realtime signal 49", "Realtime signal 50",
	"Realtime signal 51", "Realtime signal 52", "Realtime signal 53",
	"Realtime signal 54", "Realtime signal 55", "Realtime signal 56",
	"Realtime signal 57", "Realtime signal 58", "Realtime signal 59",
	"Realtime signal 60", "Realtime signal 61", "Realtime signal 62",
	"Realtime signal 63", "Realtime signal 64"
};

static inline const char *
getprogname(void)
{
#if defined(MIXTAR_BRIDGE_PROGNAME)
	return MIXTAR_BRIDGE_PROGNAME;
#endif
#if defined(MIXTAR_BRIDGE_VI_PROGNAME)
	return "vi";
#endif
#if defined(__GLIBC__)
	if (program_invocation_short_name != NULL &&
	    program_invocation_short_name[0] != '\0')
		return program_invocation_short_name;
#endif
	return "mixtar-tool";
}

static inline void
setprogname(const char *argv0)
{
#if defined(__GLIBC__)
	const char *base;

	if (argv0 == NULL || argv0[0] == '\0')
		return;
	base = strrchr(argv0, '/');
	program_invocation_short_name = (char *)(base != NULL ? base + 1 : argv0);
#else
	(void)argv0;
#endif
}

static inline int
uid_from_user(const char *name, uid_t *uid)
{
	struct passwd *pw;

	if (name == NULL || uid == NULL)
		return -1;
	pw = getpwnam(name);
	if (pw == NULL)
		return -1;
	*uid = pw->pw_uid;
	return 0;
}

static inline int
gid_from_group(const char *name, gid_t *gid)
{
	struct group *gr;

	if (name == NULL || gid == NULL)
		return -1;
	gr = getgrnam(name);
	if (gr == NULL)
		return -1;
	*gid = gr->gr_gid;
	return 0;
}

#if defined(__GLIBC__)
static inline char *
fgetln(FILE *stream, size_t *len)
{
	static char *line;
	static size_t cap;
	ssize_t nread;

	nread = getline(&line, &cap, stream);
	if (nread < 0)
		return NULL;
	if (len != NULL)
		*len = (size_t)nread;
	return line;
}
#endif

static inline wchar_t *
fgetwln(FILE *stream, size_t *len)
{
	static wchar_t *wline;
	static size_t wcap;
	char *line;
	size_t bytes;
	size_t need;
	size_t converted;

	line = fgetln(stream, &bytes);
	if (line == NULL)
		return NULL;
	need = mbstowcs(NULL, line, 0);
	if (need == (size_t)-1) {
		errno = EILSEQ;
		return NULL;
	}
	if (need + 1 > wcap) {
		wchar_t *next = reallocarray(wline, need + 1, sizeof(*wline));
		if (next == NULL)
			return NULL;
		wline = next;
		wcap = need + 1;
	}
	converted = mbstowcs(wline, line, need + 1);
	if (converted == (size_t)-1)
		return NULL;
	if (len != NULL)
		*len = converted;
	return wline;
}

#if defined(MIXTAR_BRIDGE_EMULATE_REG_STARTEND)
static inline int
mixtar_bridge_regexec(const regex_t *preg, const char *string, size_t nmatch,
    regmatch_t pmatch[], int eflags)
{
	regoff_t start;
	regoff_t end;
	size_t span;
	char *slice;
	regmatch_t *local;
	size_t i;
	int rc;

	if ((eflags & REG_STARTEND) == 0 || pmatch == NULL || nmatch == 0)
		return regexec(preg, string, nmatch, pmatch, eflags & ~REG_STARTEND);

	start = pmatch[0].rm_so;
	end = pmatch[0].rm_eo;
	if (start < 0 || end < start)
		return REG_NOMATCH;

	span = (size_t)(end - start);
	slice = malloc(span + 1);
	if (slice == NULL)
		return REG_ESPACE;
	memcpy(slice, string + start, span);
	slice[span] = '\0';

	local = calloc(nmatch, sizeof(*local));
	if (local == NULL) {
		free(slice);
		return REG_ESPACE;
	}

	rc = regexec(preg, slice, nmatch, local, eflags & ~REG_STARTEND);
	if (rc == 0) {
		for (i = 0; i < nmatch; i++) {
			if (local[i].rm_so >= 0) {
				pmatch[i].rm_so = local[i].rm_so + start;
				pmatch[i].rm_eo = local[i].rm_eo + start;
			} else {
				pmatch[i].rm_so = -1;
				pmatch[i].rm_eo = -1;
			}
		}
	}

	free(local);
	free(slice);
	return rc;
}
#define regexec(preg, string, nmatch, pmatch, eflags) \
	mixtar_bridge_regexec((preg), (string), (nmatch), (pmatch), (eflags))
#endif

#if defined(__linux__) && !defined(__GLIBC__)
static inline uint32_t
arc4random(void)
{
	static uint32_t fallback_state = 0x9e3779b9u;
	uint32_t value;
	FILE *fp;

	fp = fopen("/dev/urandom", "rb");
	if (fp != NULL) {
		if (fread(&value, sizeof(value), 1, fp) == 1) {
			fclose(fp);
			return value;
		}
		fclose(fp);
	}

	fallback_state = fallback_state * 1103515245u + 12345u;
	return fallback_state;
}

static inline uint32_t
arc4random_uniform(uint32_t upper_bound)
{
	uint32_t value;
	uint32_t minimum;

	if (upper_bound < 2)
		return 0;

	minimum = (uint32_t)(-upper_bound % upper_bound);
	do {
		value = arc4random();
	} while (value < minimum);

	return value % upper_bound;
}

static inline void
arc4random_buf(void *buffer, size_t length)
{
	unsigned char *out;
	uint32_t value;
	size_t i;
	size_t j;

	out = buffer;
	i = 0;
	while (i < length) {
		value = arc4random();
		j = 0;
		while (j < sizeof(value) && i < length) {
			out[i] = (unsigned char)((value >> (j * 8)) & 0xffu);
			i++;
			j++;
		}
	}
}
#endif

static inline int
mergesort(void *base, size_t nmemb, size_t size,
    int (*compar)(const void *, const void *))
{
	qsort(base, nmemb, size, compar);
	return 0;
}

static inline int
heapsort(void *base, size_t nmemb, size_t size,
    int (*compar)(const void *, const void *))
{
	qsort(base, nmemb, size, compar);
	return 0;
}

static inline const char *
devname(dev_t dev, mode_t type)
{
	static char name[64];

	(void)type;
	snprintf(name, sizeof(name), "%u,%u", major(dev), minor(dev));
	return name;
}

static inline char *
mkdtemps(char *template_path, int suffixlen)
{
	static const char alphabet[] =
	    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	size_t len, xs;
	char *suffix, *start;
	unsigned int attempt, i;

	if (template_path == NULL || suffixlen < 0) {
		errno = EINVAL;
		return NULL;
	}
	len = strlen(template_path);
	if ((size_t)suffixlen > len) {
		errno = EINVAL;
		return NULL;
	}
	suffix = template_path + len - suffixlen;
	start = suffix;
	while (start > template_path && start[-1] == 'X')
		start--;
	xs = (size_t)(suffix - start);
	if (xs < 6) {
		errno = EINVAL;
		return NULL;
	}
	for (attempt = 0; attempt < 10000; attempt++) {
		unsigned int seed = (unsigned int)getpid() ^ (attempt * 1103515245U);
		for (i = 0; i < xs; i++) {
			seed = seed * 1103515245U + 12345U;
			start[i] = alphabet[(seed >> 16) % (sizeof(alphabet) - 1)];
		}
		if (mkdir(template_path, 0700) == 0)
			return template_path;
		if (errno != EEXIST)
			return NULL;
	}
	errno = EEXIST;
	return NULL;
}

static inline char *
fparseln(FILE *stream, size_t *len, size_t *lineno, const char delim[3],
    int flags)
{
	char *line = NULL;
	size_t cap = 0;
	ssize_t nread;

	(void)delim;
	(void)flags;
	nread = getline(&line, &cap, stream);
	if (nread < 0) {
		free(line);
		return NULL;
	}
	if (lineno != NULL)
		(*lineno)++;
	while (nread > 0 && (line[nread - 1] == '\n' ||
	    line[nread - 1] == '\r'))
		line[--nread] = '\0';
	if (len != NULL)
		*len = (size_t)nread;
	return line;
}

static inline int
fpurge(FILE *stream)
{
#if defined(__GLIBC__)
	__fpurge(stream);
	return 0;
#else
	return fflush(stream);
#endif
}

#ifndef timespecclear
#define timespecclear(tsp) ((tsp)->tv_sec = (tsp)->tv_nsec = 0)
#endif

#ifndef timespecisset
#define timespecisset(tsp) ((tsp)->tv_sec || (tsp)->tv_nsec)
#endif

#ifndef timespeccmp
#define timespeccmp(tsp, usp, cmp) \
	(((tsp)->tv_sec == (usp)->tv_sec) ? \
	((tsp)->tv_nsec cmp (usp)->tv_nsec) : \
	((tsp)->tv_sec cmp (usp)->tv_sec))
#endif

#ifndef timespecadd
#define timespecadd(tsp, usp, vsp) do { \
	(vsp)->tv_sec = (tsp)->tv_sec + (usp)->tv_sec; \
	(vsp)->tv_nsec = (tsp)->tv_nsec + (usp)->tv_nsec; \
	if ((vsp)->tv_nsec >= 1000000000L) { \
		(vsp)->tv_sec++; \
		(vsp)->tv_nsec -= 1000000000L; \
	} \
} while (0)
#endif

#ifndef timespecsub
#define timespecsub(tsp, usp, vsp) do { \
	(vsp)->tv_sec = (tsp)->tv_sec - (usp)->tv_sec; \
	(vsp)->tv_nsec = (tsp)->tv_nsec - (usp)->tv_nsec; \
	if ((vsp)->tv_nsec < 0) { \
		(vsp)->tv_sec--; \
		(vsp)->tv_nsec += 1000000000L; \
	} \
} while (0)
#endif

static inline void
srandom_deterministic(unsigned int seed)
{
	srandom(seed);
}

static inline int
mixtar_bridge_has_token(const char *text, const char *token)
{
	size_t token_len;

	if (text == NULL || token == NULL)
		return 0;
	token_len = strlen(token);
	while (*text != '\0') {
		while (*text == ' ' || *text == '\t')
			text++;
		if (strncmp(text, token, token_len) == 0 &&
		    (text[token_len] == '\0' || text[token_len] == ' ' ||
		    text[token_len] == '\t'))
			return 1;
		while (*text != '\0' && *text != ' ' && *text != '\t')
			text++;
	}
	return 0;
}

static inline int
mixtar_bridge_parse_unveil_perms(const char *permissions)
{
	int perms = 0;

	if (permissions == NULL)
		return 0;
	for (; *permissions != '\0'; permissions++) {
		if (*permissions == 'r')
			perms |= MIXTAR_PLEDGE_RPATH;
		else if (*permissions == 'w')
			perms |= MIXTAR_PLEDGE_WPATH;
		else if (*permissions == 'c')
			perms |= MIXTAR_PLEDGE_CPATH;
		else if (*permissions == 'x')
			perms |= MIXTAR_PLEDGE_EXEC;
		else {
			errno = EINVAL;
			return -1;
		}
	}
	return perms;
}

static inline int
mixtar_bridge_trim_trailing_slashes(char *path)
{
	size_t len;

	if (path == NULL) {
		errno = EINVAL;
		return -1;
	}
	len = strlen(path);
	while (len > 1 && path[len - 1] == '/') {
		path[len - 1] = '\0';
		len--;
	}
	return 0;
}

static inline int
mixtar_bridge_abs_path(const char *path, char *out, size_t out_len)
{
	char cwd[PATH_MAX];
	int written;

	if (path == NULL || out == NULL || out_len == 0) {
		errno = EINVAL;
		return -1;
	}
	if (path[0] == '/') {
		if (snprintf(out, out_len, "%s", path) >= (int)out_len) {
			errno = ENAMETOOLONG;
			return -1;
		}
		return mixtar_bridge_trim_trailing_slashes(out);
	}
	if (getcwd(cwd, sizeof(cwd)) == NULL)
		return -1;
	written = snprintf(out, out_len, "%s/%s", cwd, path);
	if (written < 0 || written >= (int)out_len) {
		errno = ENAMETOOLONG;
		return -1;
	}
	return mixtar_bridge_trim_trailing_slashes(out);
}

static inline int
mixtar_bridge_path_prefix_match(const char *path, const char *prefix)
{
	size_t len;

	if (strcmp(prefix, "/") == 0)
		return 1;
	len = strlen(prefix);
	if (strncmp(path, prefix, len) != 0)
		return 0;
	return path[len] == '\0' || path[len] == '/';
}

static inline int
mixtar_bridge_pledge_allows(int needed)
{
	unsigned int mask = (unsigned int)needed;

	if (!mixtar_bridge_pledge_active)
		return 1;
	if ((mixtar_bridge_pledge_mask & mask) == mask)
		return 1;
	errno = EPERM;
	return 0;
}

static inline int
mixtar_bridge_unveil_allows(const char *path, int needed)
{
	char abs_path[PATH_MAX];
	int i;

	if (mixtar_bridge_unveil_count == 0)
		return 1;
	if (mixtar_bridge_abs_path(path, abs_path, sizeof(abs_path)) != 0)
		return 0;
	for (i = 0; i < mixtar_bridge_unveil_count; i++) {
		if (mixtar_bridge_path_prefix_match(abs_path,
		    mixtar_bridge_unveil_rules[i].path) &&
		    (mixtar_bridge_unveil_rules[i].perms & needed) == needed)
			return 1;
	}
	errno = EACCES;
	return 0;
}

static inline int
mixtar_bridge_path_allows(const char *path, int needed)
{
	return mixtar_bridge_pledge_allows(needed) &&
	    mixtar_bridge_unveil_allows(path, needed);
}

static inline int
pledge(const char *promises, const char *execpromises)
{
	(void)execpromises;
	mixtar_bridge_pledge_active = 1;
	mixtar_bridge_pledge_mask = 0;
	if (promises == NULL)
		return 0;
	if (mixtar_bridge_has_token(promises, "stdio"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_STDIO;
	if (mixtar_bridge_has_token(promises, "rpath"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_RPATH;
	if (mixtar_bridge_has_token(promises, "wpath"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_WPATH;
	if (mixtar_bridge_has_token(promises, "cpath"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_CPATH;
	if (mixtar_bridge_has_token(promises, "tmppath"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_TMPPATH |
		    MIXTAR_PLEDGE_WPATH | MIXTAR_PLEDGE_CPATH;
	if (mixtar_bridge_has_token(promises, "inet"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_INET;
	if (mixtar_bridge_has_token(promises, "dns"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_DNS;
	if (mixtar_bridge_has_token(promises, "proc"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_PROC;
	if (mixtar_bridge_has_token(promises, "exec"))
		mixtar_bridge_pledge_mask |= MIXTAR_PLEDGE_EXEC;
	return 0;
}

static inline int
unveil(const char *path, const char *permissions)
{
	int perms;
	char abs_path[PATH_MAX];

	if (path == NULL && permissions == NULL) {
		mixtar_bridge_unveil_locked = 1;
		return 0;
	}
	if (path == NULL || permissions == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (mixtar_bridge_unveil_locked) {
		errno = EPERM;
		return -1;
	}
	if (mixtar_bridge_unveil_count >= MIXTAR_BRIDGE_UNVEIL_MAX) {
		errno = ENOSPC;
		return -1;
	}
	perms = mixtar_bridge_parse_unveil_perms(permissions);
	if (perms < 0)
		return -1;
	if (mixtar_bridge_abs_path(path, abs_path, sizeof(abs_path)) != 0)
		return -1;
	snprintf(mixtar_bridge_unveil_rules[mixtar_bridge_unveil_count].path,
	    sizeof(mixtar_bridge_unveil_rules[mixtar_bridge_unveil_count].path),
	    "%s", abs_path);
	mixtar_bridge_unveil_rules[mixtar_bridge_unveil_count].perms = perms;
	mixtar_bridge_unveil_count++;
	return 0;
}

static inline int
mixtar_bridge_open_needed(int flags)
{
	int needed = 0;

	switch (flags & O_ACCMODE) {
	case O_RDWR:
		needed |= MIXTAR_PLEDGE_RPATH | MIXTAR_PLEDGE_WPATH;
		break;
	case O_WRONLY:
		needed |= MIXTAR_PLEDGE_WPATH;
		break;
	default:
		needed |= MIXTAR_PLEDGE_RPATH;
		break;
	}
	if ((flags & (O_TRUNC | O_APPEND)) != 0)
		needed |= MIXTAR_PLEDGE_WPATH;
	if ((flags & O_CREAT) != 0)
		needed |= MIXTAR_PLEDGE_CPATH;
	return needed;
}

static inline int
mixtar_bridge_open(const char *path, int flags, ...)
{
	mode_t mode = 0;
	int needed = mixtar_bridge_open_needed(flags);

	if (!mixtar_bridge_path_allows(path, needed))
		return -1;
	if ((flags & O_CREAT) != 0) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
		return open(path, flags, mode);
	}
	return open(path, flags);
}

static inline int
mixtar_bridge_openat(int dirfd, const char *path, int flags, ...)
{
	mode_t mode = 0;
	int needed = mixtar_bridge_open_needed(flags);

	if (path != NULL && path[0] != '/')
		return openat(dirfd, path, flags);
	if (!mixtar_bridge_path_allows(path, needed))
		return -1;
	if ((flags & O_CREAT) != 0) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
		return openat(dirfd, path, flags, mode);
	}
	return openat(dirfd, path, flags);
}

static inline int
mixtar_bridge_mkstemp(char *template_path)
{
	static const char alphabet[] =
	    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
	char *end;
	char *start;
	uint64_t seed;
	size_t run_len;
	size_t i;
	int attempt;
	int fd;

	if (template_path == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (!mixtar_bridge_path_allows(template_path,
	    MIXTAR_PLEDGE_WPATH | MIXTAR_PLEDGE_CPATH))
		return -1;

	end = template_path + strlen(template_path);
	start = end;
	while (start > template_path && start[-1] == 'X')
		start--;
	run_len = (size_t)(end - start);
	if (run_len < 6) {
		errno = EINVAL;
		return -1;
	}

	seed = ((uint64_t)(uintptr_t)template_path) ^
	    ((uint64_t)getpid() << 32) ^ (uint64_t)time(NULL);
	for (attempt = 0; attempt < 512; attempt++) {
		uint64_t value = seed + (uint64_t)attempt * 0x9e3779b97f4a7c15ULL;
		for (i = 0; i < run_len; i++) {
			value = value * 2862933555777941757ULL + 3037000493ULL;
			start[i] = alphabet[value % (sizeof(alphabet) - 1)];
		}
		fd = open(template_path, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd >= 0)
			return fd;
		if (errno != EEXIST)
			return -1;
	}
	errno = EEXIST;
	return -1;
}

static inline FILE *
mixtar_bridge_fopen(const char *path, const char *mode)
{
	int needed = 0;

	if (mode == NULL || strchr(mode, 'r') != NULL ||
	    strchr(mode, '+') != NULL)
		needed |= MIXTAR_PLEDGE_RPATH;
	if (mode != NULL && (strchr(mode, 'w') != NULL ||
	    strchr(mode, 'a') != NULL || strchr(mode, '+') != NULL))
		needed |= MIXTAR_PLEDGE_WPATH;
	if (mode != NULL && (strchr(mode, 'w') != NULL ||
	    strchr(mode, 'a') != NULL))
		needed |= MIXTAR_PLEDGE_CPATH;
	if (!mixtar_bridge_path_allows(path, needed))
		return NULL;
	return fopen(path, mode);
}

static inline int
mixtar_bridge_stat(const char *path, struct stat *sb)
{
	if (!mixtar_bridge_path_allows(path, MIXTAR_PLEDGE_RPATH))
		return -1;
	return stat(path, sb);
}

static inline int
mixtar_bridge_lstat(const char *path, struct stat *sb)
{
	if (!mixtar_bridge_path_allows(path, MIXTAR_PLEDGE_RPATH))
		return -1;
	return lstat(path, sb);
}

static inline int
mixtar_bridge_access(const char *path, int mode)
{
	int needed = MIXTAR_PLEDGE_RPATH;

	if ((mode & W_OK) != 0)
		needed |= MIXTAR_PLEDGE_WPATH;
	if (!mixtar_bridge_path_allows(path, needed))
		return -1;
	return access(path, mode);
}

static inline int
mixtar_bridge_unlink(const char *path)
{
	if (!mixtar_bridge_path_allows(path, MIXTAR_PLEDGE_CPATH))
		return -1;
	return unlink(path);
}

static inline int
mixtar_bridge_mkdir(const char *path, mode_t mode)
{
	if (!mixtar_bridge_path_allows(path, MIXTAR_PLEDGE_CPATH))
		return -1;
	return mkdir(path, mode);
}

static inline int
mixtar_bridge_rmdir(const char *path)
{
	if (!mixtar_bridge_path_allows(path, MIXTAR_PLEDGE_CPATH))
		return -1;
	return rmdir(path);
}

static inline int
mixtar_bridge_rename(const char *oldpath, const char *newpath)
{
	if (!mixtar_bridge_path_allows(oldpath, MIXTAR_PLEDGE_CPATH) ||
	    !mixtar_bridge_path_allows(newpath, MIXTAR_PLEDGE_CPATH))
		return -1;
	return rename(oldpath, newpath);
}

static inline int
mixtar_bridge_chmod(const char *path, mode_t mode)
{
	if (!mixtar_bridge_path_allows(path, MIXTAR_PLEDGE_WPATH))
		return -1;
	return chmod(path, mode);
}

#define open(...) mixtar_bridge_open(__VA_ARGS__)
#define openat(...) mixtar_bridge_openat(__VA_ARGS__)
#define mkstemp(template_path) mixtar_bridge_mkstemp((template_path))
#define fopen(path, mode) mixtar_bridge_fopen((path), (mode))
#define stat(path, sb) mixtar_bridge_stat((path), (sb))
#define lstat(path, sb) mixtar_bridge_lstat((path), (sb))
#define access(path, mode) mixtar_bridge_access((path), (mode))
#define unlink(path) mixtar_bridge_unlink((path))
#define mkdir(path, mode) mixtar_bridge_mkdir((path), (mode))
#define rmdir(path) mixtar_bridge_rmdir((path))
#define rename(oldpath, newpath) mixtar_bridge_rename((oldpath), (newpath))
#define chmod(path, mode) mixtar_bridge_chmod((path), (mode))

static inline void
warnc(int code, const char *fmt, ...)
{
	int saved_errno = errno;
	va_list ap;

	errno = code;
	va_start(ap, fmt);
	vwarn(fmt, ap);
	va_end(ap);
	errno = saved_errno;
}

static inline void __attribute__((__noreturn__))
errc(int eval, int code, const char *fmt, ...)
{
	va_list ap;

	errno = code;
	va_start(ap, fmt);
	vwarn(fmt, ap);
	va_end(ap);
	exit(eval);
}

static inline const char *
user_from_uid(unsigned long uid, int nouser)
{
	static char fallback[32];
	struct passwd *pw;

	(void)nouser;
	pw = getpwuid((uid_t)uid);
	if (pw != NULL)
		return pw->pw_name;
	snprintf(fallback, sizeof(fallback), "%lu", uid);
	return fallback;
}

static inline const char *
group_from_gid(unsigned long gid, int nogroup)
{
	static char fallback[32];
	struct group *gr;

	(void)nogroup;
	gr = getgrgid((gid_t)gid);
	if (gr != NULL)
		return gr->gr_name;
	snprintf(fallback, sizeof(fallback), "%lu", gid);
	return fallback;
}

static inline void
setproctitle(const char *fmt, ...)
{
	(void)fmt;
}

#endif

#endif
