#ifndef MIXTAR_BRIDGE_PWD_H
#define MIXTAR_BRIDGE_PWD_H

#pragma GCC system_header

#include_next <pwd.h>

#include <stdlib.h>
#include <string.h>

#ifndef _PW_NAME_LEN
#define _PW_NAME_LEN 255
#endif

#ifndef pw_expire
#define pw_expire pw_uid
#endif

static inline char *
mixtar_bridge_pwd_strdup(const char *value)
{
	if (value == NULL)
		value = "";
	return strdup(value);
}

static inline struct passwd *
pw_dup(const struct passwd *pw)
{
	struct passwd *out;

	if (pw == NULL)
		return NULL;
	out = (struct passwd *)calloc(1, sizeof(*out));
	if (out == NULL)
		return NULL;
	out->pw_name = mixtar_bridge_pwd_strdup(pw->pw_name);
	out->pw_passwd = mixtar_bridge_pwd_strdup(pw->pw_passwd);
	out->pw_uid = pw->pw_uid;
	out->pw_gid = pw->pw_gid;
	out->pw_gecos = mixtar_bridge_pwd_strdup(pw->pw_gecos);
	out->pw_dir = mixtar_bridge_pwd_strdup(pw->pw_dir);
	out->pw_shell = mixtar_bridge_pwd_strdup(pw->pw_shell);
	if (out->pw_name == NULL || out->pw_passwd == NULL ||
	    out->pw_gecos == NULL || out->pw_dir == NULL ||
	    out->pw_shell == NULL) {
		free(out->pw_name);
		free(out->pw_passwd);
		free(out->pw_gecos);
		free(out->pw_dir);
		free(out->pw_shell);
		free(out);
		return NULL;
	}
	return out;
}

#ifdef MIXTAR_PASSWD_COMPAT

#ifndef pw_change
#define pw_change pw_gid
#endif

#ifndef _PASSWORD_OMITV7
#define _PASSWORD_OMITV7 0x01
#endif

#ifndef _PASSWORD_SECUREONLY
#define _PASSWORD_SECUREONLY 0x02
#endif

static inline void
pw_init(void)
{
}

static inline int
pw_lock(int retries)
{
	(void)retries;
	return -1;
}

static inline void
pw_abort(void)
{
}

static inline void
pw_error(const char *name, int err, int eval)
{
	(void)name;
	(void)err;
	if (eval)
		exit(eval);
}

static inline void
pw_copy(int from, int to, const struct passwd *pw, const struct passwd *old_pw)
{
	(void)from;
	(void)to;
	(void)pw;
	(void)old_pw;
}

static inline int
pw_mkdb(const char *user, int flags)
{
	(void)user;
	(void)flags;
	return -1;
}

#endif /* MIXTAR_PASSWD_COMPAT */

#endif /* MIXTAR_BRIDGE_PWD_H */
