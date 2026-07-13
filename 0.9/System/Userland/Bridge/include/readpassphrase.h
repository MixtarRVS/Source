/* Mixtar Bridge readpassphrase.h compatibility shim. */
#ifndef MIXTAR_BRIDGE_READPASSPHRASE_H
#define MIXTAR_BRIDGE_READPASSPHRASE_H

#include <stdio.h>
#include <string.h>

#define RPP_ECHO_ON     0x00
#define RPP_ECHO_OFF    0x01
#define RPP_REQUIRE_TTY 0x02
#define RPP_FORCELOWER  0x04
#define RPP_FORCEUPPER  0x08
#define RPP_SEVENBIT    0x10
#define RPP_STDIN       0x20

static inline char *
readpassphrase(const char *prompt, char *buf, size_t bufsiz, int flags)
{
	size_t len;

	(void)flags;
	if (buf == NULL || bufsiz == 0)
		return NULL;
	if (prompt != NULL) {
		fputs(prompt, stderr);
		fflush(stderr);
	}
	if (fgets(buf, bufsiz, stdin) == NULL)
		return NULL;
	len = strlen(buf);
	if (len != 0 && buf[len - 1] == '\n')
		buf[len - 1] = '\0';
	return buf;
}

#endif
