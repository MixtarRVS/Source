#include <errno.h>
#include <sha2.h>
#include <stdio.h>
#include <string.h>

enum { MIXTAR_SHA256_BUFFER_SIZE = 64 * 1024 };

static int
hash_file(const char *path)
{
    FILE *input;
    SHA2_CTX context;
    unsigned char buffer[MIXTAR_SHA256_BUFFER_SIZE];
    unsigned char digest[SHA256_DIGEST_LENGTH];
    size_t count;
    size_t index;

    input = fopen(path, "rb");
    if (input == NULL) {
        fprintf(stderr, "mixtar-sha256: %s: %s\n", path, strerror(errno));
        return 1;
    }

    SHA256Init(&context);
    while ((count = fread(buffer, 1, sizeof(buffer), input)) != 0)
        SHA256Update(&context, buffer, count);

    if (ferror(input)) {
        fprintf(stderr, "mixtar-sha256: %s: read failed\n", path);
        fclose(input);
        return 1;
    }
    if (fclose(input) != 0) {
        fprintf(stderr, "mixtar-sha256: %s: close failed\n", path);
        return 1;
    }

    SHA256Final(digest, &context);
    for (index = 0; index < sizeof(digest); index++)
        printf("%02x", digest[index]);
    putchar('\n');
    return ferror(stdout) ? 1 : 0;
}

int
main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: mixtar-sha256 FILE\n");
        return 64;
    }
    return hash_file(argv[1]);
}
