#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

enum {
    K_UNICODE = 0x03,
    KDSKBMODE = 0x4b45,
    KDSKBENT = 0x4b47,
    MIXTAR_ALTGR_TABLE = 1U << 1,
    MIXTAR_SHIFT_ALTGR_TABLE = (1U << 0) | (1U << 1),
    MIXTAR_UNICODE_TAG = 0xf000U
};

struct kbentry {
    unsigned char kb_table;
    unsigned char kb_index;
    unsigned short kb_value;
};

struct mixtar_key_pair {
    unsigned char keycode;
    unsigned short lower;
    unsigned short upper;
};

static const struct mixtar_key_pair polish_programmer_keys[] = {
    {18, 0x0119, 0x0118},
    {24, 0x00f3, 0x00d3},
    {30, 0x0105, 0x0104},
    {31, 0x015b, 0x015a},
    {38, 0x0142, 0x0141},
    {44, 0x017c, 0x017b},
    {45, 0x017a, 0x0179},
    {46, 0x0107, 0x0106},
    {49, 0x0144, 0x0143},
};

static unsigned short kernel_unicode(unsigned short codepoint)
{
    return (unsigned short)(codepoint ^ MIXTAR_UNICODE_TAG);
}

static int install_key(int fd, unsigned char table, unsigned char keycode,
                       unsigned short codepoint)
{
    struct kbentry entry = {
        .kb_table = table,
        .kb_index = keycode,
        .kb_value = kernel_unicode(codepoint),
    };
    return ioctl(fd, KDSKBENT, &entry);
}

static int install_polish_programmer_map(int fd)
{
    size_t index;

    for (index = 0; index < sizeof(polish_programmer_keys) /
                              sizeof(polish_programmer_keys[0]); ++index) {
        const struct mixtar_key_pair *key = &polish_programmer_keys[index];
        if (install_key(fd, MIXTAR_ALTGR_TABLE, key->keycode, key->lower) != 0 ||
            install_key(fd, MIXTAR_SHIFT_ALTGR_TABLE, key->keycode,
                        key->upper) != 0) {
            return -1;
        }
    }
    return 0;
}

int main(int argc, char **argv)
{
    int fd;
    int rc = 0;

    if (argc != 3) {
        fputs("usage: ConsoleSetup <console> <pl|us>\n", stderr);
        return 64;
    }
    if (strcmp(argv[2], "pl") != 0 && strcmp(argv[2], "us") != 0) {
        fputs("ConsoleSetup: unsupported keymap\n", stderr);
        return 65;
    }
    fd = open(argv[1], O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "ConsoleSetup: open failed: %s\n", strerror(errno));
        return 66;
    }
    if (ioctl(fd, KDSKBMODE, K_UNICODE) != 0) {
        if (errno != ENOTTY) {
            fprintf(stderr, "ConsoleSetup: Unicode mode failed: %s\n",
                    strerror(errno));
            rc = 67;
        }
    } else if (strcmp(argv[2], "pl") == 0 &&
               install_polish_programmer_map(fd) != 0) {
        fprintf(stderr, "ConsoleSetup: keymap install failed: %s\n",
                strerror(errno));
        rc = 68;
    }
    if (close(fd) != 0 && rc == 0) {
        rc = 69;
    }
    return rc;
}
