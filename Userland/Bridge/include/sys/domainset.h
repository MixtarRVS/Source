#ifndef MIXTAR_BRIDGE_SYS_DOMAINSET_H
#define MIXTAR_BRIDGE_SYS_DOMAINSET_H

#include <ctype.h>
#include <errno.h>
#include <sched.h>
#include <stdlib.h>
#include <string.h>
#include <sys/cpuset.h>
#include <sys/types.h>

#define DOMAINSET_SETSIZE CPU_SETSIZE

#define DOMAINSET_POLICY_INVALID 0
#define DOMAINSET_POLICY_ROUNDROBIN 1
#define DOMAINSET_POLICY_FIRSTTOUCH 2
#define DOMAINSET_POLICY_PREFER 3
#define DOMAINSET_POLICY_INTERLEAVE 4

typedef cpu_set_t domainset_t;

#define DOMAINSET_ZERO(set) CPU_ZERO(set)
#define DOMAINSET_SET(bit, set) CPU_SET((bit), (set))

static inline void
domainset_parselist(const char *list, domainset_t *domains, int *policy)
{
	const char *p = list;
	const char *colon;

	CPU_ZERO(domains);
	if (policy != NULL)
		*policy = DOMAINSET_POLICY_ROUNDROBIN;
	if (p == NULL)
		return;

	colon = strchr(p, ':');
	if (colon != NULL) {
		if (policy != NULL) {
			if (strncmp(p, "rr", (size_t)(colon - p)) == 0 ||
			    strncmp(p, "round-robin", (size_t)(colon - p)) == 0)
				*policy = DOMAINSET_POLICY_ROUNDROBIN;
			else if (strncmp(p, "first-touch", (size_t)(colon - p)) == 0)
				*policy = DOMAINSET_POLICY_FIRSTTOUCH;
			else if (strncmp(p, "prefer", (size_t)(colon - p)) == 0)
				*policy = DOMAINSET_POLICY_PREFER;
			else if (strncmp(p, "interleave", (size_t)(colon - p)) == 0)
				*policy = DOMAINSET_POLICY_INTERLEAVE;
		}
		p = colon + 1;
	}

	while (*p != '\0') {
		char *end = NULL;
		long start;
		long stop;

		while (*p == ',' || isspace((unsigned char)*p))
			p++;
		if (*p == '\0')
			break;
		start = strtol(p, &end, 10);
		if (end == p || start < 0)
			break;
		stop = start;
		p = end;
		if (*p == '-') {
			p++;
			stop = strtol(p, &end, 10);
			if (end == p || stop < start)
				break;
			p = end;
		}
		for (long domain = start; domain <= stop &&
		    domain < DOMAINSET_SETSIZE; domain++)
			CPU_SET((int)domain, domains);
		if (*p == ',')
			p++;
	}
}

static inline int
cpuset_getdomain(cpulevel_t level, cpuwhich_t which, id_t id,
    size_t setsize, domainset_t *domains, int *policy)
{
	(void)level;
	(void)which;
	(void)id;
	(void)setsize;
	if (domains == NULL || policy == NULL) {
		errno = EINVAL;
		return -1;
	}
	CPU_ZERO(domains);
	CPU_SET(0, domains);
	*policy = DOMAINSET_POLICY_ROUNDROBIN;
	return 0;
}

static inline int
cpuset_setdomain(cpulevel_t level, cpuwhich_t which, id_t id,
    size_t setsize, const domainset_t *domains, int policy)
{
	(void)level;
	(void)which;
	(void)id;
	(void)setsize;
	(void)domains;
	(void)policy;
	errno = ENOTSUP;
	return -1;
}

#endif /* MIXTAR_BRIDGE_SYS_DOMAINSET_H */
