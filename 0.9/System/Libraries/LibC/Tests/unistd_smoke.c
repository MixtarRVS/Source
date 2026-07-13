#include "unistd.h"

_Static_assert(sizeof(write(1, (void *)0, 0)) == 8, "write must return 64-bit ssize ABI");
_Static_assert(sizeof(getpid()) == 4, "getpid must return 32-bit pid ABI");
_Static_assert(sizeof(getuid()) == 4, "getuid must return 32-bit uid ABI");

int main(void) {
    char message[] = "mixtar-libc write ok\n";
    int64_t wrote = write(1, message, 21);
    if (wrote != 21) {
        return 1;
    }
    if (getpid() <= 0) {
        return 2;
    }
    if (getuid() == UINT32_MAX) {
        return 3;
    }
    if (gettid() <= 0) {
        return 4;
    }
    if (getpgrp() <= 0) {
        return 5;
    }
    if (fsync(-1) >= 0) {
        return 6;
    }
    return 0;
}
