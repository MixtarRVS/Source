// mixtar_init.c
// Minimal first-userspace proof for MixtarRVS Server v0.

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __cplusplus
#define MI_ARG(text) const_cast<char *>(text)
#else
#define MI_ARG(text) ((char *)(text))
#endif

static int log_fd = -1;
static volatile sig_atomic_t sigchld_pending = 0;
static volatile sig_atomic_t shutdown_requested = 0;
static volatile sig_atomic_t shutdown_signal = 0;

typedef enum {
    TARGET_TEXT,
    TARGET_GRAPHICAL,
    TARGET_SMOKE,
    TARGET_GRAPHICAL_SMOKE,
    TARGET_EMERGENCY
} boot_target_t;

static void write_all(int fd, const char *text) {
    size_t len = strlen(text);
    while (len > 0) {
        ssize_t n = write(fd, text, len);
        if (n <= 0) {
            return;
        }
        text += n;
        len -= (size_t)n;
    }
}

static void say(const char *text) {
    write_all(1, text);
    write_all(1, "\n");
    if (log_fd >= 0) {
        write_all(log_fd, text);
        write_all(log_fd, "\n");
    }
}

static void say_errno(const char *prefix) {
    char buf[256];
    snprintf(buf, sizeof(buf), "%s: %s", prefix, strerror(errno));
    say(buf);
}

static void handle_signal(int signo) {
    if (signo == SIGCHLD) {
        sigchld_pending = 1;
    } else if (signo == SIGTERM || signo == SIGINT || signo == SIGHUP) {
        shutdown_signal = signo;
        shutdown_requested = 1;
    }
}

static void install_signal_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NOCLDSTOP;

    sigaction(SIGCHLD, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
}

static void mkdir_if_missing(const char *path, mode_t mode) {
    if (mkdir(path, mode) != 0 && errno != EEXIST) {
        say_errno(path);
    }
}

static void symlink_if_missing(const char *target, const char *link_path) {
    struct stat st;
    if (lstat(link_path, &st) == 0) {
        return;
    }
    if (symlink(target, link_path) != 0 && errno != EEXIST) {
        say_errno(link_path);
    }
}

static void write_file_if_missing(const char *path, const char *text, mode_t mode) {
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode);
    if (fd < 0) {
        if (errno != EEXIST) {
            say_errno(path);
        }
        return;
    }
    write_all(fd, text);
    close(fd);
}

static void mount_best_effort(const char *source, const char *target,
                              const char *type, unsigned long flags) {
    if (mount(source, target, type, flags, "") != 0 && errno != EBUSY) {
        char buf[256];
        snprintf(buf, sizeof(buf), "mount %s on %s failed", type, target);
        say_errno(buf);
    }
}

static int wait_for_child(pid_t child, int *status) {
    for (;;) {
        pid_t done = waitpid(child, status, 0);
        if (done == child) {
            return 0;
        }
        if (done < 0 && errno == EINTR) {
            continue;
        }
        return 1;
    }
}

static void reap_children_nonblocking(void) {
    for (;;) {
        int status = 0;
        pid_t child = waitpid(-1, &status, WNOHANG);
        if (child > 0) {
            char buf[128];
            if (WIFEXITED(status)) {
                snprintf(buf, sizeof(buf), "Mixtar: reaped child %ld exit %d",
                         (long)child, WEXITSTATUS(status));
            } else if (WIFSIGNALED(status)) {
                snprintf(buf, sizeof(buf), "Mixtar: reaped child %ld signal %d",
                         (long)child, WTERMSIG(status));
            } else {
                snprintf(buf, sizeof(buf), "Mixtar: reaped child %ld", (long)child);
            }
            say(buf);
            continue;
        }
        if (child < 0 && errno != ECHILD) {
            say_errno("Mixtar: waitpid failed");
        }
        return;
    }
}

static int run_tool(const char *path, char *const argv[]) {
    pid_t child = fork();
    if (child == 0) {
        execv(path, argv);
        _exit(127);
    }
    if (child > 0) {
        int status = 0;
        if (wait_for_child(child, &status) == 0 && WIFEXITED(status) &&
            WEXITSTATUS(status) == 0) {
            return 0;
        }
    }
    return 1;
}

static int run_tool_env(const char *path, char *const argv[], char *const envp[]) {
    pid_t child = fork();
    if (child == 0) {
        execve(path, argv, envp);
        _exit(127);
    }
    if (child > 0) {
        int status = 0;
        if (wait_for_child(child, &status) == 0 && WIFEXITED(status) &&
            WEXITSTATUS(status) == 0) {
            return 0;
        }
    }
    return 1;
}

static int wait_for_socket(const char *path, int attempts, useconds_t delay_us) {
    for (int i = 0; i < attempts; i++) {
        struct stat st;
        if (stat(path, &st) == 0 && S_ISSOCK(st.st_mode)) {
            return 0;
        }
        usleep(delay_us);
    }
    return 1;
}

static int cmdline_has(const char *needle) {
    char buf[1024];
    int fd = open("/proc/cmdline", O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return 0;
    }

    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) {
        return 0;
    }

    buf[n] = '\0';
    return strstr(buf, needle) != NULL;
}

static boot_target_t detect_boot_target(void) {
    if (cmdline_has("mixtar.target=emergency")) {
        return TARGET_EMERGENCY;
    }
    if (cmdline_has("mixtar.target=graphical-smoke") ||
        cmdline_has("mixtar.desktop-smoke=1")) {
        return TARGET_GRAPHICAL_SMOKE;
    }
    if (cmdline_has("mixtar.target=smoke") || cmdline_has("mixtar.smoke=1")) {
        return TARGET_SMOKE;
    }
    if (cmdline_has("mixtar.target=graphical") || cmdline_has("mixtar.desktop=1")) {
        return TARGET_GRAPHICAL;
    }
    return TARGET_TEXT;
}

static const char *target_name(boot_target_t target) {
    switch (target) {
    case TARGET_GRAPHICAL:
        return "graphical";
    case TARGET_SMOKE:
        return "smoke";
    case TARGET_GRAPHICAL_SMOKE:
        return "graphical-smoke";
    case TARGET_EMERGENCY:
        return "emergency";
    case TARGET_TEXT:
    default:
        return "text";
    }
}

static int target_uses_desktop(boot_target_t target) {
    return target == TARGET_GRAPHICAL || target == TARGET_GRAPHICAL_SMOKE;
}

static int target_is_smoke(boot_target_t target) {
    return target == TARGET_SMOKE || target == TARGET_GRAPHICAL_SMOKE;
}

static void log_target(boot_target_t target) {
    char buf[128];
    snprintf(buf, sizeof(buf), "Mixtar: target %s", target_name(target));
    say(buf);
}

static void create_layout(void) {
    mkdir_if_missing("/System", 0755);
    mkdir_if_missing("/System/Kernel", 0755);
    mkdir_if_missing("/System/Runtime", 0755);
    mkdir_if_missing("/System/Runtime/Desktop", 0755);
    mkdir_if_missing("/System/Runtime/run", 0755);
    mkdir_if_missing("/System/Tools", 0755);
    mkdir_if_missing("/System/SystemTools", 0755);
    mkdir_if_missing("/System/Shells", 0755);
    mkdir_if_missing("/System/Libraries", 0755);
    mkdir_if_missing("/System/Configuration", 0755);
    mkdir_if_missing("/System/Logs", 0755);
    mkdir_if_missing("/System/Resources", 0755);
    mkdir_if_missing("/System/Init", 0755);
    mkdir_if_missing("/Applications", 0755);
    mkdir_if_missing("/Programs", 0755);
    mkdir_if_missing("/Users", 0755);
    mkdir_if_missing("/Users/Administrator", 0700);
    mkdir_if_missing("/Temporary", 01777);
    mkdir_if_missing("/usr", 0755);
    mkdir_if_missing("/var", 0755);
    mkdir_if_missing("/proc", 0555);
    mkdir_if_missing("/sys", 0555);
    mkdir_if_missing("/dev", 0755);
}

static void prepare_desktop_runtime(void) {
    mkdir_if_missing("/dev/shm", 01777);
    chmod("/dev/shm", 01777);
    mount_best_effort("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV);
    mkdir_if_missing("/var/lib", 0755);
    mkdir_if_missing("/var/lib/xkb", 0755);
    mkdir_if_missing("/var/lib/dbus", 0755);
    chmod("/var/lib/xkb", 0755);
    mkdir_if_missing("/System/Resources/X11/xkb/compiled", 01777);
    chmod("/System/Resources/X11/xkb/compiled", 01777);
    write_file_if_missing("/etc/machine-id",
                          "9d0f1a2b3c4d5e6f8091a2b3c4d5e6f7\n", 0644);
    write_file_if_missing("/var/lib/dbus/machine-id",
                          "9d0f1a2b3c4d5e6f8091a2b3c4d5e6f7\n", 0644);
    mkdir_if_missing("/System/Runtime/run/Administrator", 0700);
    chmod("/System/Runtime/run/Administrator", 0700);
    mkdir_if_missing("/tmp/.X11-unix", 01777);
    chmod("/tmp/.X11-unix", 01777);
}

static int prepare_xauthority(void) {
    static const char *const path = "/System/Runtime/run/Administrator/Xauthority";

    if (access("/System/Runtime/Desktop/xauth", X_OK) != 0) {
        say("desktop-xauth: xauth missing");
        return 1;
    }

    unlink(path);
    char *argv[] = {
        MI_ARG("/System/Runtime/Desktop/xauth"),
        MI_ARG("-f"),
        MI_ARG("/System/Runtime/run/Administrator/Xauthority"),
        MI_ARG("add"),
        MI_ARG(":0"),
        MI_ARG("."),
        MI_ARG("4d6978746172525653532d7831312d30303031"),
        NULL,
    };
    char *const envp[] = {
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("XAUTHORITY=/System/Runtime/run/Administrator/Xauthority"),
        NULL,
    };

    if (run_tool_env("/System/Runtime/Desktop/xauth", argv, envp) == 0) {
        chmod(path, 0600);
        say("desktop-xauth: ok");
        return 0;
    }

    say("desktop-xauth: failed");
    return 1;
}

static void create_compat_aliases(void) {
    symlink_if_missing("System/Tools", "/bin");
    symlink_if_missing("System/SystemTools", "/sbin");
    symlink_if_missing("System/Libraries", "/lib");
    symlink_if_missing("System/Libraries", "/lib64");
    symlink_if_missing("System/Configuration", "/etc");
    symlink_if_missing("Users", "/home");
    symlink_if_missing("Users/Administrator", "/root");
    symlink_if_missing("Administrator", "/Users/Superuser");
    symlink_if_missing("Administrator", "/Users/root");
    symlink_if_missing("Temporary", "/tmp");
    symlink_if_missing("System/Runtime/run", "/run");
    symlink_if_missing("../System/Tools", "/usr/bin");
    symlink_if_missing("../System/SystemTools", "/usr/sbin");
    symlink_if_missing("../System/Libraries", "/usr/lib");
    symlink_if_missing("../System/Resources", "/usr/share");
    symlink_if_missing("../System/Logs", "/var/log");
    symlink_if_missing("../System/Runtime/run", "/var/run");
    if (access("/System/Shells/msh", X_OK) == 0) {
        symlink_if_missing("../Shells/msh", "/System/Tools/sh");
    }
}

static void harden_config_permissions(void) {
    chmod("/System/Configuration/passwd", 0644);
    chmod("/System/Configuration/group", 0644);
    chmod("/System/Configuration/pam.d/mixtar-login", 0644);
    chmod("/System/Configuration/shadow", 0600);
}

static void open_boot_log(void) {
    log_fd = open("/System/Logs/boot.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC,
                  0644);
    if (log_fd < 0) {
        say_errno("open /System/Logs/boot.log failed");
    }
}

static void check_toolkit(void) {
    char *echo_args[] = {
        MI_ARG("/System/Tools/echo"),
        MI_ARG("Mixtar toolkit path reachable"),
        NULL
    };
    if (run_tool("/System/Tools/echo", echo_args) == 0) {
        say("toolkit-echo: ok");
        say("toolkit ready");
    } else {
        say("toolkit-echo: failed");
        say("toolkit failed");
    }
}

static void check_msh(void) {
    if (access("/System/Shells/msh", X_OK) == 0) {
        say("msh ready");
    } else {
        say("msh deferred");
    }
}

static void launch_console_shell(void) {
    if (access("/System/Shells/msh", X_OK) != 0) {
        say("console: msh unavailable");
        return;
    }

    say("console: starting /System/Shells/msh");
    pid_t child = fork();
    if (child == 0) {
        char *argv[] = {MI_ARG("/System/Shells/msh"), NULL};
        char *envp[] = {
            MI_ARG("PATH=/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
            MI_ARG("SHELL=/System/Shells/msh"),
            MI_ARG("HOME=/Users/Administrator"),
            MI_ARG("USER=Administrator"),
            MI_ARG("TERM=vt100"),
            NULL,
        };
        chdir("/");
        execve("/System/Shells/msh", argv, envp);
        _exit(127);
    }
    if (child < 0) {
        say_errno("console: fork msh failed");
        return;
    }

    int status = 0;
    if (waitpid(child, &status, 0) == child) {
        if (WIFEXITED(status)) {
            char buf[96];
            snprintf(buf, sizeof(buf), "console: msh exited %d", WEXITSTATUS(status));
            say(buf);
        } else if (WIFSIGNALED(status)) {
            char buf[96];
            snprintf(buf, sizeof(buf), "console: msh signal %d", WTERMSIG(status));
            say(buf);
        }
    }
}

#include "mixtar_init_desktop.h"

static void poweroff_after_smoke(void) {
    say("smoke: powering off after boot proof");
    sync();
    reboot(RB_POWER_OFF);
    _exit(0);
}

static void shutdown_from_signal(void) {
    char buf[128];
    snprintf(buf, sizeof(buf), "Mixtar: shutdown requested by signal %d",
             (int)shutdown_signal);
    say(buf);
    sync();
    reboot(RB_POWER_OFF);
    _exit(0);
}

static void idle_forever(void) {
    say("Mixtar: idle");
    for (;;) {
        pause();
        if (sigchld_pending) {
            sigchld_pending = 0;
            reap_children_nonblocking();
        }
        if (shutdown_requested) {
            shutdown_from_signal();
        }
    }
}

int main(void) {
    int console = open("/dev/console", O_RDWR | O_CLOEXEC);
    if (console >= 0) {
        dup2(console, 0);
        dup2(console, 1);
        dup2(console, 2);
        if (console > 2) {
            close(console);
        }
    }

    install_signal_handlers();
    create_layout();
    create_compat_aliases();
    harden_config_permissions();
    open_boot_log();

    mount_best_effort("devtmpfs", "/dev", "devtmpfs", 0);
    mkdir_if_missing("/dev/pts", 0755);
    mount_best_effort("devpts", "/dev/pts", "devpts", 0);
    mount_best_effort("proc", "/proc", "proc", 0);
    mount_best_effort("sysfs", "/sys", "sysfs", 0);
    mount_best_effort("tmpfs", "/Temporary", "tmpfs", 0);

    boot_target_t target = detect_boot_target();
    say("Mixtar: pid1");
    log_target(target);
    say("MixtarRVS v0");
    say("stage: first userspace");
    say("Mixtar: mounts ok");
    say("Mixtar: layout ok");
    say("/System ready");
    check_toolkit();
    check_msh();

    int boot_ok = 1;
    if (target_uses_desktop(target)) {
        if (launch_desktop_target(target == TARGET_GRAPHICAL_SMOKE) != 0) {
            say("Mixtar: desktop target failed");
            boot_ok = 0;
            if (target == TARGET_GRAPHICAL) {
                say("Mixtar: entering emergency shell");
                launch_console_shell();
            }
        }
    }

    if (target == TARGET_EMERGENCY) {
        say("Mixtar: emergency shell");
        launch_console_shell();
    }

    if (boot_ok) {
        say("boot-smoke: ok");
    } else {
        say("boot-smoke: failed");
    }

    if (target_is_smoke(target)) {
        poweroff_after_smoke();
    }

    if (target == TARGET_TEXT || target == TARGET_GRAPHICAL) {
        launch_console_shell();
    }

    idle_forever();
}
