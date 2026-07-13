#include "mixtar_signify_compat.h"

#include <stdint.h>
#include <string.h>

int
pledge(const char *promises, const char *execpromises)
{
	(void)promises;
	(void)execpromises;
	return 0;
}

const char *
getprogname(void)
{
	return "signify";
}

size_t
strlcpy(char *destination, const char *source, size_t size)
{
	size_t source_length = strlen(source);

	if (size != 0) {
		size_t count = source_length;
		if (count >= size)
			count = size - 1;
		memcpy(destination, source, count);
		destination[count] = '\0';
	}
	return source_length;
}

int
timingsafe_bcmp(const void *left, const void *right, size_t length)
{
	const uint8_t *a = left;
	const uint8_t *b = right;
	uint8_t difference = 0;
	size_t index;

	for (index = 0; index < length; index++)
		difference |= a[index] ^ b[index];
	return difference;
}
