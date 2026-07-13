static void harden_desktop_binary(const char *path) {
    if (access(path, F_OK) != 0) {
        return;
    }
    chown(path, 0, 0);
    chmod(path, 0755);
}

static void harden_desktop_data_file(const char *path) {
    if (access(path, F_OK) != 0) {
        return;
    }
    chown(path, 0, 0);
    chmod(path, 0644);
}

static void harden_desktop_runtime_permissions(void) {
    chown("/System/Runtime/Desktop", 0, 0);
    chmod("/System/Runtime/Desktop", 0755);

    harden_desktop_binary("/System/Runtime/Desktop/mddm");
    harden_desktop_binary("/System/Runtime/Desktop/mixtar-shell");
    harden_desktop_binary("/System/Runtime/Desktop/dbus-daemon");
    harden_desktop_binary("/System/Runtime/Desktop/labwc");
    harden_desktop_binary("/System/Runtime/Desktop/Xwayland");
    harden_desktop_binary("/System/Runtime/Desktop/Xwayland.real");
    harden_desktop_binary("/System/Runtime/Desktop/xauth");
    harden_desktop_binary("/System/Runtime/Desktop/xterm");
    harden_desktop_binary("/System/Runtime/Desktop/xkbcomp");
    harden_desktop_binary("/System/Runtime/Desktop/xdpyinfo");
    harden_desktop_binary("/System/Runtime/Desktop/ailang-ui-smoke");
    harden_desktop_binary("/System/Runtime/Desktop/mixtarrvs-panel");

    harden_desktop_data_file("/System/Runtime/Desktop/mddm.conf");
    harden_desktop_data_file("/System/Runtime/Desktop/shortcuts.conf");
    harden_desktop_data_file("/System/Runtime/Desktop/context-menus.conf");
}

static pid_t launch_desktop_panel(void) {
    if (access("/System/Runtime/Desktop/mixtarrvs-panel", X_OK) != 0) {
        say("desktop-panel: missing");
        return -1;
    }

    char *const envp[] = {
        MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
        MI_ARG("DBUS_SESSION_BUS_ADDRESS=unix:path=/System/Runtime/run/Administrator/bus"),
        MI_ARG("WAYLAND_DISPLAY=wayland-0"),
        MI_ARG("XDG_DATA_DIRS=/usr/share"),
        MI_ARG("LANG=C.utf8"),
        MI_ARG("LC_ALL=C.utf8"),
        MI_ARG("TZ=Europe/Warsaw"),
        MI_ARG("FONTCONFIG_PATH=/System/Configuration/fonts"),
        MI_ARG("FONTCONFIG_FILE=/System/Configuration/fonts/fonts.conf"),
        MI_ARG("XCURSOR_PATH=/System/Resources/icons:/usr/share/icons"),
        MI_ARG("XCURSOR_THEME=mixtar-aero"),
        MI_ARG("XCURSOR_SIZE=32"),
        MI_ARG("GDK_BACKEND=wayland"),
        MI_ARG("GTK_A11Y=none"),
        MI_ARG("NO_AT_BRIDGE=1"),
        NULL,
    };

    say("desktop-panel: starting");
    pid_t child = fork();
    if (child == 0) {
        char *argv[] = {MI_ARG("/System/Runtime/Desktop/mixtarrvs-panel"), NULL};
        chdir("/");
        execve("/System/Runtime/Desktop/mixtarrvs-panel", argv, envp);
        _exit(127);
    }
    if (child < 0) {
        say_errno("desktop-panel: fork failed");
        return -1;
    }

    usleep(500000);
    int status = 0;
    pid_t done = waitpid(child, &status, WNOHANG);
    if (done == 0) {
        say("desktop-panel: ok");
        return child;
    }
    if (done == child && WIFEXITED(status)) {
        char buf[96];
        snprintf(buf, sizeof(buf), "desktop-panel: exited %d", WEXITSTATUS(status));
        say(buf);
    } else if (done == child && WIFSIGNALED(status)) {
        char buf[96];
        snprintf(buf, sizeof(buf), "desktop-panel: signal %d", WTERMSIG(status));
        say(buf);
    } else {
        say_errno("desktop-panel: wait failed");
    }
    return -1;
}

static int run_ailang_ui_smoke(void) {
    if (access("/System/Runtime/Desktop/ailang-ui-smoke", X_OK) != 0) {
        say("ailang-ui-smoke: missing");
        return 1;
    }

    char *argv[] = {MI_ARG("/System/Runtime/Desktop/ailang-ui-smoke"), NULL};
    char *const envp[] = {
        MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
        MI_ARG("DBUS_SESSION_BUS_ADDRESS=unix:path=/System/Runtime/run/Administrator/bus"),
        MI_ARG("WAYLAND_DISPLAY=wayland-0"),
        MI_ARG("AILANG_UI_DEMO_FRAMES=2"),
        MI_ARG("AILANG_LEAK_REPORT=1"),
        MI_ARG("LANG=C.utf8"),
        MI_ARG("LC_ALL=C.utf8"),
        MI_ARG("TZ=Europe/Warsaw"),
        MI_ARG("FONTCONFIG_PATH=/System/Configuration/fonts"),
        MI_ARG("FONTCONFIG_FILE=/System/Configuration/fonts/fonts.conf"),
        MI_ARG("XCURSOR_PATH=/System/Resources/icons:/usr/share/icons"),
        MI_ARG("XCURSOR_THEME=mixtar-aero"),
        MI_ARG("XCURSOR_SIZE=32"),
        NULL,
    };
    if (run_tool_env("/System/Runtime/Desktop/ailang-ui-smoke", argv, envp) == 0) {
        say("ailang-ui-smoke: ok");
        return 0;
    }

    say("ailang-ui-smoke: failed");
    return 1;
}

static pid_t launch_desktop_terminal(void) {
    if (access("/System/Runtime/Desktop/xterm", X_OK) != 0) {
        say("desktop-terminal: missing");
        return -1;
    }

    char *const envp[] = {
        MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("SHELL=/System/Shells/msh"),
        MI_ARG("TERM=xterm-256color"),
        MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
        MI_ARG("WAYLAND_DISPLAY=wayland-0"),
        MI_ARG("DISPLAY=:0"),
        MI_ARG("XAUTHORITY=/System/Runtime/run/Administrator/Xauthority"),
        MI_ARG("DBUS_SESSION_BUS_ADDRESS=unix:path=/System/Runtime/run/Administrator/bus"),
        MI_ARG("XDG_DATA_DIRS=/usr/share"),
        MI_ARG("LANG=C.utf8"),
        MI_ARG("LC_ALL=C.utf8"),
        MI_ARG("TZ=Europe/Warsaw"),
        MI_ARG("FONTCONFIG_PATH=/System/Configuration/fonts"),
        MI_ARG("FONTCONFIG_FILE=/System/Configuration/fonts/fonts.conf"),
        MI_ARG("XCURSOR_PATH=/System/Resources/icons:/usr/share/icons"),
        MI_ARG("XCURSOR_THEME=mixtar-aero"),
        MI_ARG("XCURSOR_SIZE=32"),
        MI_ARG("NO_AT_BRIDGE=1"),
        NULL,
    };

    say("desktop-terminal: starting");
    pid_t child = fork();
    if (child == 0) {
        char *argv[] = {
            MI_ARG("/System/Runtime/Desktop/xterm"),
            MI_ARG("-hold"),
            MI_ARG("-fa"),
            MI_ARG("DejaVu Sans Mono"),
            MI_ARG("-fs"),
            MI_ARG("11"),
            MI_ARG("-e"),
            MI_ARG("/System/Shells/msh"),
            NULL,
        };
        chdir("/");
        execve("/System/Runtime/Desktop/xterm", argv, envp);
        _exit(127);
    }
    if (child < 0) {
        say_errno("desktop-terminal: fork failed");
        return -1;
    }

    usleep(700000);
    int status = 0;
    if (waitpid(child, &status, WNOHANG) == 0) {
        say("desktop-terminal: ok");
        return child;
    }
    say("desktop-terminal: failed");
    return -1;
}

static int seed_one_input_udev_property(int index, const char *sys_path) {
    static int mknod_error_logged = 0;
    static int db_error_logged = 0;

    int sys_fd = open(sys_path, O_RDONLY | O_CLOEXEC);
    if (sys_fd < 0) {
        return 0;
    }

    char dev_text[32];
    ssize_t used = read(sys_fd, dev_text, sizeof(dev_text) - 1);
    close(sys_fd);
    if (used <= 0) {
        return 0;
    }
    dev_text[used] = '\0';

    unsigned int maj = 0;
    unsigned int min = 0;
    if (sscanf(dev_text, "%u:%u", &maj, &min) != 2) {
        return 0;
    }

    char event_path[64];
    snprintf(event_path, sizeof(event_path), "/dev/input/event%d", index);
    if (mknod(event_path, S_IFCHR | 0600, makedev(maj, min)) != 0 &&
        errno != EEXIST) {
        if (mknod_error_logged == 0) {
            char buf[160];
            snprintf(buf, sizeof(buf), "desktop-input: mknod %s failed: %s",
                     event_path, strerror(errno));
            say(buf);
            mknod_error_logged = 1;
        }
        return 0;
    }

    char db_path[96];
    snprintf(db_path, sizeof(db_path), "/run/udev/data/c%u:%u", maj, min);
    int fd = open(db_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) {
        if (db_error_logged == 0) {
            char buf[160];
            snprintf(buf, sizeof(buf), "desktop-input: open %s failed: %s",
                     db_path, strerror(errno));
            say(buf);
            db_error_logged = 1;
        }
        return 0;
    }

    write_all(fd, "E:ID_INPUT=1\n");
    write_all(fd, "E:ID_INPUT_KEY=1\n");
    write_all(fd, "E:ID_INPUT_KEYBOARD=1\n");
    write_all(fd, "E:ID_INPUT_MOUSE=1\n");
    close(fd);
    return 1;
}

static void log_input_sysfs_entries(void) {
    DIR *dir = opendir("/sys/class/input");
    if (dir == NULL) {
        say_errno("desktop-input: open /sys/class/input failed");
        return;
    }

    int count = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL && count < 32) {
        if (entry->d_name[0] == '.') {
            continue;
        }
        char buf[128];
        snprintf(buf, sizeof(buf), "desktop-input-sys: %s", entry->d_name);
        say(buf);
        ++count;
    }
    closedir(dir);

    if (count == 0) {
        say("desktop-input-sys: empty");
    }
}

static int seed_input_udev_properties(void) {
    mkdir("/dev/input", 0755);
    mkdir("/System/Runtime/run/udev", 0755);
    mkdir("/System/Runtime/run/udev/data", 0755);
    mkdir("/run/udev", 0755);
    mkdir("/run/udev/data", 0755);

    log_input_sysfs_entries();

    int seeded = 0;
    for (int attempt = 0; attempt < 20 && seeded == 0; ++attempt) {
        for (int event_index = 0; event_index < 128; ++event_index) {
            char sys_path[80];
            snprintf(sys_path, sizeof(sys_path), "/sys/class/input/event%d/dev", event_index);
            seeded += seed_one_input_udev_property(event_index, sys_path);
        }
        for (int input_index = 0; input_index < 64; ++input_index) {
            for (int event_index = 0; event_index < 128; ++event_index) {
                char sys_path[96];
                snprintf(sys_path, sizeof(sys_path),
                         "/sys/class/input/input%d/event%d/dev",
                         input_index, event_index);
                seeded += seed_one_input_udev_property(event_index, sys_path);
            }
        }
        if (seeded == 0) {
            usleep(50000);
        }
    }

    if (seeded > 0) {
        char buf[96];
        snprintf(buf, sizeof(buf), "desktop-input: seeded %d event device(s)", seeded);
        say(buf);
        return 0;
    }

    say("desktop-input: no event devices");
    return 1;
}

#include "mixtar_init_dbus.h"

static int run_mddm_login_smoke(void) {
    if (!cmdline_has("mixtar.mddm=1")) {
        return 0;
    }
    harden_desktop_runtime_permissions();
    if (access("/System/Runtime/Desktop/mddm", X_OK) != 0) {
        say("mddm-smoke: missing");
        return 1;
    }

    char *argv[] = {
        MI_ARG("/System/Runtime/Desktop/mddm"),
        MI_ARG("--smoke-login"),
        MI_ARG("--wayland-socket-name"),
        MI_ARG("mddm-smoke-0"),
        NULL
    };
    char *const envp[] = {
        MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("SHELL=/System/Shells/msh"),
        MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
        MI_ARG("WAYLAND_DISPLAY=wayland-0"),
        MI_ARG("DISPLAY=:0"),
        MI_ARG("XAUTHORITY=/System/Runtime/run/Administrator/Xauthority"),
        MI_ARG("DBUS_SESSION_BUS_ADDRESS=unix:path=/System/Runtime/run/Administrator/bus"),
        MI_ARG("MDDM_USE_SESSION_BUS=1"),
        MI_ARG("QT_QPA_PLATFORM=wayland"),
        MI_ARG("QT_PLUGIN_PATH=/System/Resources/qt6/plugins"),
        MI_ARG("QML2_IMPORT_PATH=/System/Resources/qt6/qml"),
        MI_ARG("QT_QUICK_BACKEND=software"),
        MI_ARG("XDG_DATA_DIRS=/usr/share"),
        MI_ARG("LANG=C.utf8"),
        MI_ARG("LC_ALL=C.utf8"),
        MI_ARG("TZ=Europe/Warsaw"),
        MI_ARG("FONTCONFIG_PATH=/System/Configuration/fonts"),
        MI_ARG("FONTCONFIG_FILE=/System/Configuration/fonts/fonts.conf"),
        MI_ARG("QT_QPA_FONTDIR=/System/Resources/fonts/truetype/dejavu"),
        MI_ARG("XCURSOR_PATH=/System/Resources/icons:/usr/share/icons"),
        MI_ARG("XCURSOR_THEME=mixtar-aero"),
        MI_ARG("XCURSOR_SIZE=32"),
        MI_ARG("XKB_CONFIG_ROOT=/usr/share/X11/xkb"),
        MI_ARG("XLOCALEDIR=/usr/share/X11/locale"),
        MI_ARG("GTK_A11Y=none"),
        MI_ARG("NO_AT_BRIDGE=1"),
        NULL,
    };

    say("mddm-smoke: starting");
    if (run_tool_env("/System/Runtime/Desktop/mddm", argv, envp) == 0) {
        say("mddm-smoke: ok");
        return 0;
    }

    say("mddm-smoke: failed");
    return 1;
}

static pid_t launch_mddm_login_session(void) {
    if (!cmdline_has("mixtar.mddm=1")) {
        return -1;
    }
    harden_desktop_runtime_permissions();
    if (access("/System/Runtime/Desktop/mddm", X_OK) != 0) {
        say("mddm-greeter: missing");
        return -1;
    }

    char *const envp[] = {
        MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("SHELL=/System/Shells/msh"),
        MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
        MI_ARG("WAYLAND_DISPLAY=wayland-0"),
        MI_ARG("DISPLAY=:0"),
        MI_ARG("XAUTHORITY=/System/Runtime/run/Administrator/Xauthority"),
        MI_ARG("DBUS_SESSION_BUS_ADDRESS=unix:path=/System/Runtime/run/Administrator/bus"),
        MI_ARG("MDDM_USE_SESSION_BUS=1"),
        MI_ARG("QT_QPA_PLATFORM=wayland"),
        MI_ARG("QT_PLUGIN_PATH=/System/Resources/qt6/plugins"),
        MI_ARG("QML2_IMPORT_PATH=/System/Resources/qt6/qml"),
        MI_ARG("QT_QUICK_BACKEND=software"),
        MI_ARG("XDG_DATA_DIRS=/usr/share"),
        MI_ARG("LANG=C.utf8"),
        MI_ARG("LC_ALL=C.utf8"),
        MI_ARG("TZ=Europe/Warsaw"),
        MI_ARG("FONTCONFIG_PATH=/System/Configuration/fonts"),
        MI_ARG("FONTCONFIG_FILE=/System/Configuration/fonts/fonts.conf"),
        MI_ARG("QT_QPA_FONTDIR=/System/Resources/fonts/truetype/dejavu"),
        MI_ARG("XCURSOR_PATH=/System/Resources/icons:/usr/share/icons"),
        MI_ARG("XCURSOR_THEME=mixtar-aero"),
        MI_ARG("XCURSOR_SIZE=32"),
        MI_ARG("XKB_CONFIG_ROOT=/usr/share/X11/xkb"),
        MI_ARG("XLOCALEDIR=/usr/share/X11/locale"),
        MI_ARG("NO_AT_BRIDGE=1"),
        NULL,
    };

    say("mddm-greeter: starting");
    pid_t child = fork();
    if (child == 0) {
        char *argv[] = {
            MI_ARG("/System/Runtime/Desktop/mddm"),
            MI_ARG("--fullscreen"),
            MI_ARG("--wayland-socket-name"),
            MI_ARG("mddm-0"),
            NULL,
        };
        chdir("/");
        execve("/System/Runtime/Desktop/mddm", argv, envp);
        _exit(127);
    }
    if (child < 0) {
        say_errno("mddm-greeter: fork failed");
        return -1;
    }

    usleep(1000000);
    int status = 0;
    pid_t done = waitpid(child, &status, WNOHANG);
    if (done == 0) {
        say("mddm-auth-backend: production");
        say("mddm-greeter: ok");
        return child;
    }
    if (done == child && WIFEXITED(status)) {
        char buf[96];
        snprintf(buf, sizeof(buf), "mddm-greeter: exited %d", WEXITSTATUS(status));
        say(buf);
    } else if (done == child && WIFSIGNALED(status)) {
        char buf[96];
        snprintf(buf, sizeof(buf), "mddm-greeter: signal %d", WTERMSIG(status));
        say(buf);
    } else {
        say_errno("mddm-greeter: wait failed");
    }
    return -1;
}

static int launch_desktop_target(int smoke_mode) {
    int rc = 0;

    if (access("/System/Runtime/Desktop/labwc", X_OK) != 0) {
        say("desktop: labwc missing");
        return 1;
    }

    if (access("/System/Runtime/Desktop/Xwayland", X_OK) != 0) {
        say("desktop: Xwayland missing");
        return 1;
    }

    prepare_desktop_runtime();
    seed_input_udev_properties();
    if (prepare_xauthority() != 0) {
        return 1;
    }
    say("desktop: starting labwc");

    char *const envp[] = {
        MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
        MI_ARG("HOME=/Users/Administrator"),
        MI_ARG("USER=Administrator"),
        MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
        MI_ARG("XAUTHORITY=/System/Runtime/run/Administrator/Xauthority"),
        MI_ARG("XDG_DATA_DIRS=/usr/share"),
        MI_ARG("LANG=C.utf8"),
        MI_ARG("LC_ALL=C.utf8"),
        MI_ARG("TZ=Europe/Warsaw"),
        MI_ARG("FONTCONFIG_PATH=/System/Configuration/fonts"),
        MI_ARG("FONTCONFIG_FILE=/System/Configuration/fonts/fonts.conf"),
        MI_ARG("XCURSOR_PATH=/System/Resources/icons:/usr/share/icons"),
        MI_ARG("XCURSOR_THEME=mixtar-aero"),
        MI_ARG("XCURSOR_SIZE=32"),
        MI_ARG("GDK_BACKEND=wayland"),
        MI_ARG("GTK_A11Y=none"),
        MI_ARG("NO_AT_BRIDGE=1"),
        MI_ARG("LIBSEAT_BACKEND=builtin"),
        MI_ARG("WLR_RENDERER=pixman"),
        MI_ARG("XKB_CONFIG_ROOT=/usr/share/X11/xkb"),
        MI_ARG("XKB_DEFAULT_RULES=evdev"),
        MI_ARG("XKB_DEFAULT_MODEL=pc105"),
        MI_ARG("XKB_DEFAULT_LAYOUT=us"),
        MI_ARG("XLOCALEDIR=/usr/share/X11/locale"),
        NULL,
    };

    pid_t child = fork();
    if (child == 0) {
        char *argv[] = {MI_ARG("/System/Runtime/Desktop/labwc"), NULL};
        chdir("/");
        execve("/System/Runtime/Desktop/labwc", argv, envp);
        _exit(127);
    }
    if (child < 0) {
        say_errno("desktop: fork labwc failed");
        return 1;
    }

    if (wait_for_socket("/System/Runtime/run/Administrator/wayland-0", 100, 50000) == 0) {
        say("desktop-wayland: ok");
    } else {
        say("desktop-wayland: failed");
        rc = 1;
    }

    pid_t dbus = launch_desktop_dbus();
    if (cmdline_has("mixtar.dbus=1") && dbus <= 0) {
        rc = 1;
    }

    if (!smoke_mode && cmdline_has("mixtar.mddm=1")) {
        pid_t mddm = launch_mddm_login_session();
        if (mddm > 0 && rc == 0) {
            say("desktop-session: ready");
            return 0;
        }
        rc = 1;
        if (dbus > 0) {
            kill(dbus, SIGTERM);
            waitpid(dbus, NULL, 0);
            say("desktop-dbus: stopped");
        }
        kill(child, SIGTERM);
        waitpid(child, NULL, 0);
        say("desktop: labwc stopped");
        return rc;
    }

    pid_t panel = launch_desktop_panel();
    if (panel <= 0) {
        rc = 1;
    }
    pid_t terminal = launch_desktop_terminal();
    if (terminal <= 0) {
        rc = 1;
    }

    if (!smoke_mode) {
        if (rc == 0) {
            say("desktop-session: ready");
            return 0;
        }
        if (terminal > 0) {
            kill(terminal, SIGTERM);
            waitpid(terminal, NULL, 0);
            say("desktop-terminal: stopped");
        }
        if (dbus > 0) {
            kill(dbus, SIGTERM);
            waitpid(dbus, NULL, 0);
            say("desktop-dbus: stopped");
        }
        if (panel > 0) {
            kill(panel, SIGTERM);
            waitpid(panel, NULL, 0);
            say("desktop-panel: stopped");
        }
        kill(child, SIGTERM);
        waitpid(child, NULL, 0);
        say("desktop: labwc stopped");
        return rc;
    }

    if (run_ailang_ui_smoke() != 0) {
        rc = 1;
    }

    if (access("/System/Runtime/Desktop/xdpyinfo", X_OK) == 0) {
        char *xargv[] = {
            MI_ARG("/System/Runtime/Desktop/xdpyinfo"),
            MI_ARG("-display"),
            MI_ARG(":0"),
            NULL
        };
        char *const xenvp[] = {
            MI_ARG("PATH=/System/Runtime/Desktop:/System/Tools:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"),
            MI_ARG("HOME=/Users/Administrator"),
            MI_ARG("USER=Administrator"),
            MI_ARG("DISPLAY=:0"),
            MI_ARG("XAUTHORITY=/System/Runtime/run/Administrator/Xauthority"),
            NULL,
        };
        if (run_tool_env("/System/Runtime/Desktop/xdpyinfo", xargv, xenvp) == 0) {
            say("desktop-x11-smoke: ok");
        } else {
            say("desktop-x11-smoke: failed");
            rc = 1;
        }
    } else {
        say("desktop-x11-smoke: xdpyinfo missing");
        rc = 1;
    }

    if (run_mddm_login_smoke() != 0) {
        rc = 1;
    }

    if (panel > 0) {
        kill(panel, SIGTERM);
        waitpid(panel, NULL, 0);
        say("desktop-panel: stopped");
    }
    if (terminal > 0) {
        kill(terminal, SIGTERM);
        waitpid(terminal, NULL, 0);
        say("desktop-terminal: stopped");
    }
    if (dbus > 0) {
        kill(dbus, SIGTERM);
        waitpid(dbus, NULL, 0);
        say("desktop-dbus: stopped");
    }
    kill(child, SIGTERM);
    waitpid(child, NULL, 0);
    say("desktop: labwc stopped");
    return rc;
}
