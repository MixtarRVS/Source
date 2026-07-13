#ifndef MIXTAR_BRIDGE_VI_COMPAT_H
#define MIXTAR_BRIDGE_VI_COMPAT_H
#pragma GCC system_header

#include <db.h>

#ifndef TCSASOFT
#define TCSASOFT 0
#endif

#ifndef INFTIM
#define INFTIM -1
#endif

#ifndef MAX_REC_NUMBER
#define MAX_REC_NUMBER UINT32_MAX
#endif

#ifdef O_PATH
#undef O_PATH
#endif

#endif /* MIXTAR_BRIDGE_VI_COMPAT_H */
