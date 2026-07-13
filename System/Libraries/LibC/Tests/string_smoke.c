#include <stddef.h>
#include <stdio.h>
#include <string.h>

size_t strlcpy(char *dst, const char *src, size_t dstsize);
size_t strlcat(char *dst, const char *src, size_t dstsize);

static int check_strlcpy_full_copy(void)
{
	char buf[8] = {0};
	size_t rc = strlcpy(buf, "abc", sizeof(buf));

	if (rc != 3)
		return 1;
	if (strcmp(buf, "abc") != 0)
		return 2;
	return 0;
}

static int check_strlcpy_truncates_and_reports_source_len(void)
{
	char buf[4] = {'x', 'x', 'x', 'x'};
	size_t rc = strlcpy(buf, "abcdef", sizeof(buf));

	if (rc != 6)
		return 3;
	if (memcmp(buf, "abc", 4) != 0)
		return 4;
	return 0;
}

static int check_strlcpy_zero_size_does_not_write(void)
{
	char buf[3] = {'x', 'y', 'z'};
	size_t rc = strlcpy(buf, "abc", 0);

	if (rc != 3)
		return 5;
	if (buf[0] != 'x' || buf[1] != 'y' || buf[2] != 'z')
		return 6;
	return 0;
}

static int check_strlcat_full_append(void)
{
	char buf[8] = "ab";
	size_t rc = strlcat(buf, "cde", sizeof(buf));

	if (rc != 5)
		return 7;
	if (strcmp(buf, "abcde") != 0)
		return 8;
	return 0;
}

static int check_strlcat_truncates_and_reports_attempted_len(void)
{
	char buf[5] = "ab";
	size_t rc = strlcat(buf, "cdef", sizeof(buf));

	if (rc != 6)
		return 9;
	if (memcmp(buf, "abcd", 5) != 0)
		return 10;
	return 0;
}

static int check_strlcat_full_destination_does_not_write(void)
{
	char buf[3] = {'a', 'b', 'c'};
	size_t rc = strlcat(buf, "def", sizeof(buf));

	if (rc != 6)
		return 11;
	if (buf[0] != 'a' || buf[1] != 'b' || buf[2] != 'c')
		return 12;
	return 0;
}

int main(void)
{
	int rc;

	rc = check_strlcpy_full_copy();
	if (rc != 0)
		return rc;
	rc = check_strlcpy_truncates_and_reports_source_len();
	if (rc != 0)
		return rc;
	rc = check_strlcpy_zero_size_does_not_write();
	if (rc != 0)
		return rc;
	rc = check_strlcat_full_append();
	if (rc != 0)
		return rc;
	rc = check_strlcat_truncates_and_reports_attempted_len();
	if (rc != 0)
		return rc;
	rc = check_strlcat_full_destination_does_not_write();
	if (rc != 0)
		return rc;

	puts("string_smoke: ok");
	return 0;
}
