/* Mixtar Bridge libutil compatibility shim. */
#ifndef MIXTAR_BRIDGE_LIBUTIL_H
#define MIXTAR_BRIDGE_LIBUTIL_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#define HN_DECIMAL   0x01
#define HN_NOSPACE   0x02
#define HN_B         0x04
#define HN_AUTOSCALE 0

#ifndef FMT_SCALED_STRSIZE
#define FMT_SCALED_STRSIZE 7
#endif

#ifndef MIXTAR_BRIDGE_HAS_GETBSIZE
static inline char *
getbsize(int *headerlen, long *blocksize)
{
	static char header[] = "512-blocks";

	if (headerlen != NULL)
		*headerlen = (int)strlen(header);
	if (blocksize != NULL)
		*blocksize = 512;
	return header;
}
#endif

static inline int
humanize_number(char *buf, size_t len, long long number, const char *suffix,
    int scale, int flags)
{
	(void)scale;
	(void)flags;
	if (suffix == NULL)
		suffix = "";
	return snprintf(buf, len, "%lld%s", number, suffix);
}

static inline int
fmt_scaled(long long number, char *result)
{
	if (result == NULL)
		return -1;
	(void)snprintf(result, FMT_SCALED_STRSIZE, "%lld", number);
	return 0;
}

static inline int
scan_scaled(char *scaled, long long *result)
{
	char *end = NULL;

	if (scaled == NULL || result == NULL)
		return -1;
	*result = strtoll(scaled, &end, 10);
	if (end == scaled || *end != '\0')
		return -1;
	return 0;
}

static inline int
opendev(const char *path, int oflags, int dflags, char **realp)
{
	(void)dflags;
	if (realp != NULL)
		*realp = (char *)path;
	return open(path, oflags);
}

static inline char *
readlabelfs(const char *device, int verbose)
{
	(void)device;
	(void)verbose;
	return NULL;
}

#endif
