/* Mixtar Bridge wrapper for Linux utmp paths.
 *
 * Upstream BSD tools include <utmp.h> after the forced Bridge header.  glibc
 * then defines _PATH_UTMP back to /var/run/utmp, which WSL may not expose.
 * Keep the system ABI from include_next, then restore the Bridge path hook.
 */
#ifndef MIXTAR_BRIDGE_UTMP_WRAPPER_H
#define MIXTAR_BRIDGE_UTMP_WRAPPER_H

#if defined(__GNUC__)
#pragma GCC system_header
#endif

#if defined(__unused)
#define MIXTAR_BRIDGE_RESTORE_UNUSED 1
#undef __unused
#endif

#include_next <utmp.h>

#if defined(MIXTAR_BRIDGE_RESTORE_UNUSED)
#define __unused __attribute__((__unused__))
#undef MIXTAR_BRIDGE_RESTORE_UNUSED
#endif

#if defined(MIXTAR_BRIDGE) && defined(__linux__)
#undef _PATH_UTMP
#define _PATH_UTMP mixtar_bridge_utmp_path()
#endif

#if defined(MIXTAR_BRIDGE) && defined(__linux__) && !defined(__GLIBC__)
static inline void
login(const struct utmp *entry)
{
	(void)entry;
}
#endif

#endif
