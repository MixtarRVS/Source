#include <md5.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int check_md5end_with_stack_buffer(void)
{
	MD5_CTX ctx;
	char buf[MD5_DIGEST_STRING_LENGTH];
	char *out;

	MD5Init(&ctx);
	MD5Update(&ctx, (const unsigned char *)"abc", 3);
	out = MD5End(&ctx, buf);
	if (out != buf)
		return 1;
	if (strcmp(buf, "900150983cd24fb0d6963f7d28e17f72") != 0)
		return 2;
	return 0;
}

static int check_md5end_allocates_buffer(void)
{
	MD5_CTX ctx;
	char *out;
	int rc;

	MD5Init(&ctx);
	MD5Update(&ctx, (const unsigned char *)"abc", 3);
	out = MD5End(&ctx, NULL);
	if (out == NULL)
		return 3;
	rc = strcmp(out, "900150983cd24fb0d6963f7d28e17f72") == 0 ? 0 : 4;
	free(out);
	return rc;
}

int main(void)
{
	int rc;

	rc = check_md5end_with_stack_buffer();
	if (rc != 0)
		return rc;
	rc = check_md5end_allocates_buffer();
	if (rc != 0)
		return rc;

	puts("md5_end_smoke: ok");
	return 0;
}
