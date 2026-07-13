#ifndef MIXTAR_BRIDGE_KENV_H
#define MIXTAR_BRIDGE_KENV_H

#include <errno.h>
#include <stddef.h>
#include <string.h>

#define KENV_GET 0
#define KENV_SET 1
#define KENV_UNSET 2
#define KENV_DUMP 3
#define KENV_DUMP_LOADER 4
#define KENV_DUMP_STATIC 5

static inline int
mixtar_kenv_add(char *buf, int len, int used, const char *name,
    const char *value)
{
	int need = (int)strlen(name) + 1 + (int)strlen(value) + 1;

	if (buf != NULL && used + need < len) {
		memcpy(buf + used, name, strlen(name));
		used += (int)strlen(name);
		buf[used++] = '=';
		memcpy(buf + used, value, strlen(value));
		used += (int)strlen(value);
		buf[used++] = '\0';
	} else {
		used += need;
	}
	return used;
}

static inline int
mixtar_kenv_dump(char *buf, int len)
{
	int used = 0;

	used = mixtar_kenv_add(buf, len, used, "mixtar.system", "MixtarRVS");
	used = mixtar_kenv_add(buf, len, used, "mixtar.kernel", "linux");
	if (buf != NULL && used < len)
		buf[used] = '\0';
	else
		used++;
	return used;
}

static inline int
kenv(int action, const char *name, char *value, int len)
{
	if (action == KENV_DUMP || action == KENV_DUMP_LOADER ||
	    action == KENV_DUMP_STATIC)
		return mixtar_kenv_dump(value, len);
	if (action == KENV_GET) {
		const char *out = NULL;

		if (name == NULL || value == NULL || len <= 0) {
			errno = EINVAL;
			return -1;
		}
		if (strcmp(name, "mixtar.system") == 0)
			out = "MixtarRVS";
		else if (strcmp(name, "mixtar.kernel") == 0)
			out = "linux";
		else {
			errno = ENOENT;
			return -1;
		}
		if ((int)strlen(out) + 1 > len) {
			errno = ENOMEM;
			return -1;
		}
		strcpy(value, out);
		return 0;
	}
	if (action == KENV_SET || action == KENV_UNSET) {
		errno = ENOTSUP;
		return -1;
	}
	errno = EINVAL;
	return -1;
}

#endif /* MIXTAR_BRIDGE_KENV_H */
