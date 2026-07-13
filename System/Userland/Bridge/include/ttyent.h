#ifndef MIXTAR_BRIDGE_TTYENT_H
#define MIXTAR_BRIDGE_TTYENT_H

/*
 * Minimal OpenBSD ttyent surface for source-porting init on Linux.
 *
 * The first MixtarRVS certification tier never runs init as PID 1 and never
 * starts getty sessions. These accessors expose an empty tty table so the
 * OpenBSD source can compile unchanged while real boot orchestration stays out
 * of this userland smoke target.
 */

struct ttyent {
	char *ty_name;
	char *ty_getty;
	char *ty_type;
	int ty_status;
	char *ty_window;
	char *ty_comment;
};

#ifndef TTY_ON
#define TTY_ON 0x01
#endif

#ifndef TTY_SECURE
#define TTY_SECURE 0x02
#endif

#ifndef TTY_LOCAL
#define TTY_LOCAL 0x04
#endif

#ifndef TTY_DIALUP
#define TTY_DIALUP 0x08
#endif

#ifndef TTY_NETWORK
#define TTY_NETWORK 0x10
#endif

static inline struct ttyent *
getttyent(void)
{
	return (struct ttyent *)0;
}

static inline struct ttyent *
getttynam(const char *name)
{
	(void)name;
	return (struct ttyent *)0;
}

static inline int
setttyent(void)
{
	return 1;
}

static inline int
endttyent(void)
{
	return 1;
}

#endif /* MIXTAR_BRIDGE_TTYENT_H */
