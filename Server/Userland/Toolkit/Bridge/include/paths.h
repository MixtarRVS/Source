#ifndef MIXTAR_BRIDGE_PATHS_H
#define MIXTAR_BRIDGE_PATHS_H

#pragma GCC system_header

#include_next <paths.h>

#ifndef _PATH_BOOTDIR
#define _PATH_BOOTDIR "/boot/"
#endif

#ifndef _PATH_AUTHPROGDIR
#define _PATH_AUTHPROGDIR "/usr/libexec/auth"
#endif

#ifndef _PATH_SHELLS
#define _PATH_SHELLS "/etc/shells"
#endif

#ifndef _PATH_DEVDB
#define _PATH_DEVDB "/var/run/dev.db"
#endif

#ifndef _PATH_NOLOGIN
#define _PATH_NOLOGIN "/etc/nologin"
#endif

#ifndef _PATH_MASTERPASSWD
#define _PATH_MASTERPASSWD "/etc/master.passwd"
#endif

#ifndef _PATH_MASTERPASSWD_LOCK
#define _PATH_MASTERPASSWD_LOCK "/etc/ptmp"
#endif

#ifndef _PATH_PWD_MKDB
#define _PATH_PWD_MKDB "/usr/sbin/pwd_mkdb"
#endif

#endif /* MIXTAR_BRIDGE_PATHS_H */
