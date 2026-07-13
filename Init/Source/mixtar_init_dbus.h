static pid_t launch_desktop_dbus(void) {
    if (!cmdline_has("mixtar.dbus=1")) {
        return -1;
    }
    if (access("/System/Runtime/Desktop/dbus-daemon", X_OK) != 0) {
        say("desktop-dbus: missing");
        return -1;
    }
    say("desktop-dbus: starting");
    pid_t child = fork();
    if (child == 0) {
        char *argv[] = {
            MI_ARG("/System/Runtime/Desktop/dbus-daemon"),
            MI_ARG("--session"),
            MI_ARG("--nofork"),
            MI_ARG("--nopidfile"),
            MI_ARG("--address=unix:path=/System/Runtime/run/Administrator/bus"),
            NULL,
        };
        char *envp[] = {
            MI_ARG("HOME=/Users/Administrator"),
            MI_ARG("USER=Administrator"),
            MI_ARG("XDG_RUNTIME_DIR=/System/Runtime/run/Administrator"),
            NULL,
        };
        chdir("/");
        execve("/System/Runtime/Desktop/dbus-daemon", argv, envp);
        _exit(127);
    }
    if (child < 0) {
        say_errno("desktop-dbus: fork failed");
        return -1;
    }
    usleep(300000);
    int status = 0;
    if (waitpid(child, &status, WNOHANG) == 0) {
        say("desktop-dbus: ok");
        return child;
    }
    say("desktop-dbus: failed");
    return -1;
}
