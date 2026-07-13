#ifndef MIXTAR_BRIDGE_BSD_AUTH_H
#define MIXTAR_BRIDGE_BSD_AUTH_H

#include <pwd.h>
#include <stdlib.h>

typedef struct auth_session {
	struct passwd *pwd;
	const char *name;
	int state;
} auth_session_t;

#ifndef AUTHV_INTERACTIVE
#define AUTHV_INTERACTIVE 1
#endif

#ifndef AUTHV_NAME
#define AUTHV_NAME 2
#endif

#ifndef AUTH_ALLOW
#define AUTH_ALLOW 1
#endif

#ifndef AUTH_OKAY
#define AUTH_OKAY AUTH_ALLOW
#endif

#ifndef AUTH_PWEXPIRED
#define AUTH_PWEXPIRED 2
#endif

#ifndef AUTH_SILENT
#define AUTH_SILENT 4
#endif

#ifndef AUTH_EXPIRED
#define AUTH_EXPIRED 8
#endif

static inline auth_session_t *
auth_open(void)
{
	return (auth_session_t *)calloc(1, sizeof(auth_session_t));
}

static inline int
auth_setpwd(auth_session_t *as, struct passwd *pw)
{
	if (as == NULL)
		return -1;
	as->pwd = pw;
	return 0;
}

static inline int
auth_setoption(auth_session_t *as, const char *name, const char *value)
{
	(void)as;
	(void)name;
	(void)value;
	return 0;
}

static inline void
auth_clean(auth_session_t *as)
{
	if (as != NULL) {
		as->pwd = NULL;
		as->name = NULL;
		as->state = 0;
	}
}

static inline int
auth_setitem(auth_session_t *as, int item, const char *value)
{
	if (as == NULL)
		return -1;
	if (item == AUTHV_NAME)
		as->name = value;
	(void)item;
	return 0;
}

static inline char *
auth_getitem(auth_session_t *as, int item)
{
	if (as == NULL || item != AUTHV_NAME || as->name == NULL)
		return NULL;
	return (char *)as->name;
}

static inline struct passwd *
auth_getpwd(auth_session_t *as)
{
	if (as == NULL)
		return NULL;
	if (as->pwd != NULL)
		return as->pwd;
	if (as->name != NULL)
		return getpwnam(as->name);
	return NULL;
}

static inline int
auth_verify(auth_session_t *as, const char *style, const char *challenge,
    const char *class_name, const char *last)
{
	(void)style;
	(void)challenge;
	(void)class_name;
	(void)last;
	if (as != NULL)
		as->state = 0;
	return 0;
}

static inline int
auth_getstate(auth_session_t *as)
{
	return as == NULL ? 0 : as->state;
}

static inline char *
auth_getvalue(auth_session_t *as, const char *name)
{
	(void)as;
	(void)name;
	return NULL;
}

static inline void
auth_setstate(auth_session_t *as, int state)
{
	if (as != NULL)
		as->state = state;
}

static inline int
auth_call(auth_session_t *as, const char *path, ...)
{
	(void)as;
	(void)path;
	return 0;
}

static inline void
auth_setenv(auth_session_t *as)
{
	(void)as;
}

static inline void
auth_clroptions(auth_session_t *as)
{
	(void)as;
}

static inline void
auth_clroption(auth_session_t *as, const char *name)
{
	(void)as;
	(void)name;
}

static inline void
auth_checknologin(void *lc)
{
	(void)lc;
}

static inline long long
auth_check_expire(auth_session_t *as)
{
	(void)as;
	return 0;
}

static inline void
auth_cat(const char *path)
{
	(void)path;
}

static inline int
auth_approval(auth_session_t *as, void *lc, const char *user, const char *type)
{
	(void)as;
	(void)lc;
	(void)user;
	(void)type;
	return 1;
}

static inline void
auth_close(auth_session_t *as)
{
	free(as);
}

#endif /* MIXTAR_BRIDGE_BSD_AUTH_H */
