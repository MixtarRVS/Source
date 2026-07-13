#ifndef MIXTAR_BRIDGE_SYSLOG_H
#define MIXTAR_BRIDGE_SYSLOG_H
#pragma GCC system_header

#include_next <syslog.h>
#include <stdarg.h>

struct syslog_data {
	int unused;
};

#ifndef SYSLOG_DATA_INIT
#define SYSLOG_DATA_INIT { 0 }
#endif

static inline void
vsyslog_r(int priority, struct syslog_data *data, const char *message,
    va_list ap)
{
	(void)data;
	vsyslog(priority, message, ap);
}

static inline void
syslog_r(int priority, struct syslog_data *data, const char *message, ...)
{
	va_list ap;

	va_start(ap, message);
	vsyslog_r(priority, data, message, ap);
	va_end(ap);
}

#endif /* MIXTAR_BRIDGE_SYSLOG_H */
