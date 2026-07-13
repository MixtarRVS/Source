#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../Generated/libc_stdio.h"

int
main(void)
{
	FILE *fp;
	FILE *out;
	char *line;
	size_t len = 999;
	size_t lineno = 41;

	fp = tmpfile();
	if (fp == NULL)
		return 1;
	if (fputs("alpha\nbeta\r\n", fp) < 0)
		return 2;
	rewind(fp);

	line = fparseln(fp, &len, &lineno, NULL, 0);
	if (line == NULL)
		return 3;
	if (strcmp(line, "alpha") != 0 || len != 5 || lineno != 42)
		return 4;
	free(line);

	line = fparseln(fp, &len, &lineno, NULL, 0);
	if (line == NULL)
		return 5;
	if (strcmp(line, "beta") != 0 || len != 4 || lineno != 43)
		return 6;
	free(line);

	line = fparseln(fp, &len, &lineno, NULL, 0);
	if (line != NULL)
		return 7;
	fclose(fp);

	out = tmpfile();
	if (out == NULL)
		return 8;
	if (fputs("flush", out) < 0)
		return 9;
	if (fpurge(out) != 0)
		return 10;
	fclose(out);
	return 0;
}
