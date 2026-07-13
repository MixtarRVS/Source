#ifndef MIXTAR_BRIDGE_SYS_PARAM_H
#define MIXTAR_BRIDGE_SYS_PARAM_H
#pragma GCC system_header

#include_next <sys/param.h>

#ifndef DEV_BSIZE
#define DEV_BSIZE 512
#endif

#ifndef dbtob
#define dbtob(db) ((db) * DEV_BSIZE)
#endif

#endif /* MIXTAR_BRIDGE_SYS_PARAM_H */
