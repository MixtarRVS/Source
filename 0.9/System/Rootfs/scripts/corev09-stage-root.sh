#!/bin/sh
set -eu

VERSION="0.9"
KERNEL_VERSION="7.1.2"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
rootfs_dir="$repo_root/System/Rootfs"
generated_dir="$rootfs_dir/Generated"
kernel_profile_source="$repo_root/System/Kernel/Manifests/corev09-kernel-profile.json"
stage_root="$generated_dir/corev09-root"
efi_stage="$generated_dir/corev09-efi"
efi_source="$generated_dir/corev09-efi-build/MixtarRVS-$VERSION.efi"
explicit_efi_source=0

case "$repo_root" in
    /mnt/*)
        default_kernel_workspace="${HOME:-/tmp}/.cache/mixtarrvs-corev09/kernel"
        ;;
    *)
        default_kernel_workspace="$repo_root/System/Kernel/Generated"
        ;;
esac

kernel_workspace="${MIXTARRVS_COREV09_KERNEL_WORKSPACE:-$default_kernel_workspace}"
kernel_build_dir="${KERNEL_BUILD_DIR:-$kernel_workspace/build/linux-$KERNEL_VERSION-mixtar-rt}"
kernel_config="$kernel_build_dir/.config"
modules_builtin="$kernel_build_dir/modules.builtin"

usage() {
    cat <<EOF
usage: corev09-stage-root.sh [plan|stage|verify] [--root PATH] [--efi-stage PATH] [--efi-source PATH]

Defaults:
  root:      $stage_root
  efi-stage: $efi_stage

This script stages CoreV09 inside System/Rootfs/Generated only.
It is not an installer and not a deployment tool.
It does not modify Debian, ESP, EFI variables, boot order, or a live root.
EOF
}

fail() {
    printf '%s\n' "corev09-stage-root: error: $*" >&2
    exit 1
}

note() {
    printf '%s\n' "corev09-stage-root: $*"
}

require_safe_generated_path() {
    path=$1
    resolved_parent=$(CDPATH= cd -- "$(dirname -- "$path")" 2>/dev/null && pwd || true)
    [ -n "$resolved_parent" ] || fail "cannot resolve parent for $path"

    case "$resolved_parent/" in
        "$generated_dir"/*|"$generated_dir/")
            ;;
        *)
            fail "refusing path outside System/Rootfs/Generated: $path"
            ;;
    esac

    [ "$path" != "/" ] || fail "refusing filesystem root"
    [ "$path" != "$repo_root" ] || fail "refusing repo root"
    [ "$path" != "$rootfs_dir" ] || fail "refusing Rootfs directory"
    [ "$path" != "$generated_dir" ] || fail "refusing Generated directory"
}

copy_if_exists() {
    src=$1
    dst=$2
    if [ -f "$src" ]; then
        mkdir -p "$(dirname -- "$dst")"
        cp "$src" "$dst"
        chmod 0755 "$dst" || true
        note "copied $(basename -- "$src") -> $dst"
        return 0
    fi
    return 1
}

copy_tree_if_exists() {
    src=$1
    dst=$2
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        (cd "$src" && tar cf - .) | (cd "$dst" && tar xf -)
        note "copied tree $src -> $dst"
        return 0
    fi
    return 1
}

patch_corev09_zsh_runtime() {
    zsh_bin="$stage_root/System/Shells/zsh"
    runtime_src="$generated_dir/ail-native-initramfs-root/System/Terminal/ZSH/Runtime"
    runtime_dst="$stage_root/System/Shells/Runtime"
    terminfo_src="$generated_dir/ail-native-initramfs-root/System/Terminal/ZSH/Terminfo"
    terminfo_dst="$stage_root/System/Shells/Terminfo"

    copy_tree_if_exists "$runtime_src" "$runtime_dst" || true
    copy_tree_if_exists "$terminfo_src" "$terminfo_dst" || true

    if [ -x "$zsh_bin" ] && command -v patchelf >/dev/null 2>&1 && [ -f "$runtime_dst/ld-linux-x86-64.so.2" ]; then
        patchelf --set-interpreter /System/Shells/Runtime/ld-linux-x86-64.so.2 "$zsh_bin"
        patchelf --set-rpath /System/Shells/Runtime "$zsh_bin" 2>/dev/null || true
        note "patched zsh runtime -> /System/Shells/Runtime"
    fi
}

rewrite_networking_script_runtime() {
    script=$1
    [ -f "$script" ] || return 0
    sed -i \
        -e '1s|^#!/System/Terminal/ZSH/zsh|#!/System/Shells/zsh|' \
        -e 's#/System/Terminal/ZSH/Runtime#/System/Shells/Runtime#g' \
        -e 's#/System/Terminal/ZSH#/System/Shells#g' \
        "$script"
    chmod 0755 "$script"
}

build_corev09_sshd_service() {
    ssh_dir="$stage_root/System/Networking/SSH"
    src="$generated_dir/corev09-mixtar-sshd-service.c"
    cc_bin="${CC:-}"
    if [ -z "$cc_bin" ]; then
        if command -v musl-gcc >/dev/null 2>&1; then
            cc_bin=musl-gcc
        else
            cc_bin=cc
        fi
    fi
    command -v "$cc_bin" >/dev/null 2>&1 || fail "missing SSH service compiler: $cc_bin"
    mkdir -p "$ssh_dir"
    cat > "$src" <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

static int mkdir_one(const char *path, mode_t mode) {
    if (mkdir(path, mode) == 0 || errno == EEXIST) {
        return 0;
    }
    return -1;
}

static int bind_dir(const char *source, const char *target) {
    mkdir_one(target, 0755);
    if (mount(source, target, 0, MS_BIND | MS_REC, 0) == 0 || errno == EBUSY) {
        return 0;
    }
    fprintf(stderr, "mixtar-sshd-service: bind %s -> %s failed: %s\n", source, target, strerror(errno));
    return -1;
}

static void bind_required(const char *source, const char *target) {
    if (bind_dir(source, target) != 0) {
        exit(111);
    }
}

static void secure_chroot_component(const char *path) {
    if (chown(path, 0, 0) != 0) {
        fprintf(stderr, "mixtar-sshd-service: chroot component ownership %s failed: %s\n", path, strerror(errno));
        exit(111);
    }
    if (chmod(path, 0755) != 0) {
        fprintf(stderr, "mixtar-sshd-service: chroot component mode %s failed: %s\n", path, strerror(errno));
        exit(111);
    }
}

static void ensure_runtime_file(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT, 0666);
    if (fd >= 0) {
        close(fd);
        chmod(path, 0666);
    }
}

static void ensure_mode(const char *path, mode_t mode) {
    if (chmod(path, mode) != 0) {
        fprintf(stderr, "mixtar-sshd-service: chmod %s failed: %s\n", path, strerror(errno));
    }
}

static void attach_log(void) {
    int fd;
    mkdir_one("/System/Runtime/Networking", 0755);
    mkdir_one("/System/Runtime/Networking/SSH", 0755);
    mkdir_one("/Volumes/ESP/EFI/MixtarRVS", 0755);
    fd = open("/Volumes/ESP/EFI/MixtarRVS/CoreV09-sshd.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        fd = open("/System/Runtime/Networking/SSH/sshd-service.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    if (fd >= 0) {
        dup2(fd, 1);
        dup2(fd, 2);
        if (fd > 2) {
            close(fd);
        }
    }
}

int main(void) {
    const char *root = "/System/Networking/SSH/Root";
    attach_log();
    fprintf(stderr, "mixtar-sshd-service: preparing CoreV09 recovery root\n");
    if (mkdir_one(root, 0755) != 0) {
        fprintf(stderr, "mixtar-sshd-service: private root creation failed: %s\n", strerror(errno));
        return 111;
    }
    secure_chroot_component(root);
    bind_required("/System/Configuration/SSH", "/System/Networking/SSH/Root/System/Configuration/SSH");
    bind_required("/System/Runtime/Networking/SSH", "/System/Networking/SSH/Root/System/Runtime/Networking/SSH");
    bind_required("/System/Devices", "/System/Networking/SSH/Root/System/Devices");
    bind_required("/System/Process", "/System/Networking/SSH/Root/System/Process");
    bind_required("/System/Hardware", "/System/Networking/SSH/Root/System/Hardware");
    bind_required("/System/Shells", "/System/Networking/SSH/Root/System/Shells");
    bind_required("/System/Userland", "/System/Networking/SSH/Root/System/Userland");
    bind_required("/Users", "/System/Networking/SSH/Root/Users");
    bind_required("/Applications", "/System/Networking/SSH/Root/Applications");
    bind_required("/Temporary", "/System/Networking/SSH/Root/Temporary");
    bind_required("/Volumes", "/System/Networking/SSH/Root/Volumes");

    mkdir_one("/System/Networking/SSH/Root/Native", 0755);
    secure_chroot_component("/System/Networking/SSH/Root/Native");
    mkdir_one("/System/Networking/SSH/Root/Native/System", 0755);
    mkdir_one("/System/Networking/SSH/Root/Native/System/Networking", 0755);
    mkdir_one("/System/Networking/SSH/Root/Native/System/Networking/SSH", 0755);
    bind_required("/Applications", "/System/Networking/SSH/Root/Native/Applications");
    bind_required("/Users", "/System/Networking/SSH/Root/Native/Users");
    bind_required("/Temporary", "/System/Networking/SSH/Root/Native/Temporary");
    bind_required("/Volumes", "/System/Networking/SSH/Root/Native/Volumes");
    bind_required("/System/Compatibility", "/System/Networking/SSH/Root/Native/System/Compatibility");
    bind_required("/System/Configuration", "/System/Networking/SSH/Root/Native/System/Configuration");
    bind_required("/System/Devices", "/System/Networking/SSH/Root/Native/System/Devices");
    bind_required("/System/Drivers", "/System/Networking/SSH/Root/Native/System/Drivers");
    bind_required("/System/EFI", "/System/Networking/SSH/Root/Native/System/EFI");
    bind_required("/System/Hardware", "/System/Networking/SSH/Root/Native/System/Hardware");
    bind_required("/System/Init", "/System/Networking/SSH/Root/Native/System/Init");
    bind_required("/System/Kernel", "/System/Networking/SSH/Root/Native/System/Kernel");
    bind_required("/System/Libraries", "/System/Networking/SSH/Root/Native/System/Libraries");
    bind_required("/System/Logs", "/System/Networking/SSH/Root/Native/System/Logs");
    bind_required("/System/Process", "/System/Networking/SSH/Root/Native/System/Process");
    bind_required("/System/Resources", "/System/Networking/SSH/Root/Native/System/Resources");
    bind_required("/System/Runtime", "/System/Networking/SSH/Root/Native/System/Runtime");
    bind_required("/System/Security", "/System/Networking/SSH/Root/Native/System/Security");
    bind_required("/System/Shells", "/System/Networking/SSH/Root/Native/System/Shells");
    bind_required("/System/Tools", "/System/Networking/SSH/Root/Native/System/Tools");
    bind_required("/System/Userland", "/System/Networking/SSH/Root/Native/System/Userland");
    bind_required("/System/Networking/Core", "/System/Networking/SSH/Root/Native/System/Networking/Core");
    bind_required("/System/Networking/WiFi", "/System/Networking/SSH/Root/Native/System/Networking/WiFi");
    bind_required("/System/Networking/SSH/bin", "/System/Networking/SSH/Root/Native/System/Networking/SSH/bin");
    bind_required("/System/Networking/SSH/sbin", "/System/Networking/SSH/Root/Native/System/Networking/SSH/sbin");
    bind_required("/System/Networking/SSH/libexec", "/System/Networking/SSH/Root/Native/System/Networking/SSH/libexec");
    bind_required("/System/Networking/SSH/Runtime", "/System/Networking/SSH/Root/Native/System/Networking/SSH/Runtime");

    if (chroot(root) != 0) {
        fprintf(stderr, "mixtar-sshd-service: chroot failed: %s\n", strerror(errno));
        return 111;
    }
    if (chdir("/") != 0) {
        fprintf(stderr, "mixtar-sshd-service: chdir failed: %s\n", strerror(errno));
        return 111;
    }
    mkdir_one("/System", 0755);
    mkdir_one("/System/Devices", 0755);
    mkdir_one("/dev", 0755);
    mkdir_one("/run", 0755);
    mkdir_one("/run/sshd", 0755);
    mkdir_one("/var", 0755);
    mkdir_one("/var/empty", 0755);
    mkdir_one("/System/Runtime/Networking/SSH/empty", 0755);
    ensure_runtime_file("/System/Devices/null");
    ensure_runtime_file("/dev/null");
    ensure_runtime_file("/System/Devices/zero");
    ensure_runtime_file("/System/Devices/random");
    ensure_runtime_file("/System/Devices/urandom");
    ensure_mode("/System/Configuration/SSH/HostKeys", 0700);
    ensure_mode("/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key", 0600);
    ensure_mode("/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key.pub", 0644);
    ensure_mode("/System/Configuration/SSH/sshd_config", 0644);
    setenv("LD_LIBRARY_PATH", "/System/Networking/SSH/Runtime:/System/Shells/Runtime", 1);
    setenv("PATH", "/System/Networking/SSH/bin:/System/Networking/SSH/sbin:/System/Shells:/System/Userland", 1);
    char *argv[] = {
        "/System/Networking/SSH/sbin/sshd",
        "-D",
        "-e",
        "-f",
        "/System/Configuration/SSH/sshd_config",
        "-h",
        "/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key",
        0,
    };
    fprintf(stderr, "mixtar-sshd-service: exec sshd\n");
    execv(argv[0], argv);
    fprintf(stderr, "mixtar-sshd-service: exec failed: %s\n", strerror(errno));
    return 127;
}
C
    "$cc_bin" -O2 -static -Wall -Wextra -Werror -o "$ssh_dir/mixtar-sshd-service" "$src"
    chmod 0755 "$ssh_dir/mixtar-sshd-service"
    note "rebuilt CoreV09 /System/Networking/SSH/mixtar-sshd-service"
}

write_corev09_networking_service() {
    service="$stage_root/System/Networking/start-networking"
    src="$generated_dir/corev09-mixtar-networking-service.c"
    cc_bin="${CC:-}"
    if [ -z "$cc_bin" ]; then
        if command -v musl-gcc >/dev/null 2>&1; then
            cc_bin=musl-gcc
        else
            cc_bin=cc
        fi
    fi
    command -v "$cc_bin" >/dev/null 2>&1 || fail "missing networking service compiler: $cc_bin"
    mkdir -p "$stage_root/System/Networking"
    cat > "$src" <<'C'
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdint.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int log_fd = -1;

static void mkdir_one(const char *path) {
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        return;
    }
}

static void open_log(void) {
    mkdir_one("/System/Runtime/Networking");
    mkdir_one("/System/Runtime/Networking/SSH");
    mkdir_one("/System/Runtime/Networking/WiFi");
    mkdir_one("/Volumes/ESP/EFI/MixtarRVS");
    log_fd = open("/Volumes/ESP/EFI/MixtarRVS/CoreV09-last.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (log_fd < 0) {
        mkdir_one("/System/Logs");
        log_fd = open("/System/Logs/CoreV09-last.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }
}

static void log_line(const char *fmt, ...) {
    va_list ap;
    if (log_fd < 0) {
        return;
    }
    va_start(ap, fmt);
    vdprintf(log_fd, fmt, ap);
    va_end(ap);
    dprintf(log_fd, "\n");
    fsync(log_fd);
}

static void sleep_seconds(long seconds) {
    struct timespec ts;
    ts.tv_sec = seconds;
    ts.tv_nsec = 0;
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) {
    }
}

static char *const child_env[] = {
    "PATH=/System/Networking/Core:/System/Networking/WiFi/bin:/System/Networking/SSH/bin:/System/Networking/SSH/sbin:/System/Shells:/System/Userland",
    "LD_LIBRARY_PATH=/System/Networking/Core/Runtime:/System/Networking/WiFi/Runtime:/System/Networking/SSH/Runtime:/System/Shells/Runtime",
    "TERM=linux",
    0,
};

static int spawn_wait(char *const argv[]) {
    int status = 0;
    pid_t pid = fork();
    if (pid == 0) {
        if (log_fd >= 0) {
            dup2(log_fd, 1);
            dup2(log_fd, 2);
        }
        execve(argv[0], argv, child_env);
        _exit(127);
    }
    if (pid < 0) {
        log_line("networking: fork failed for %s: %s", argv[0], strerror(errno));
        return 127;
    }
    if (waitpid(pid, &status, 0) < 0) {
        log_line("networking: wait failed for %s: %s", argv[0], strerror(errno));
        return 127;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 128;
}

static int spawn_wait_to_fd(char *const argv[], int out_fd) {
    int status = 0;
    pid_t pid = fork();
    if (pid == 0) {
        if (out_fd >= 0) {
            dup2(out_fd, 1);
            dup2(out_fd, 2);
        }
        execve(argv[0], argv, child_env);
        _exit(127);
    }
    if (pid < 0) {
        if (out_fd >= 0) {
            dprintf(out_fd, "networking: fork failed for %s: %s\n", argv[0], strerror(errno));
        }
        return 127;
    }
    if (waitpid(pid, &status, 0) < 0) {
        if (out_fd >= 0) {
            dprintf(out_fd, "networking: wait failed for %s: %s\n", argv[0], strerror(errno));
        }
        return 127;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 128;
}

static pid_t spawn_background(char *const argv[], const char *name) {
    pid_t pid = fork();
    if (pid == 0) {
        if (log_fd >= 0) {
            dup2(log_fd, 1);
            dup2(log_fd, 2);
        }
        execve(argv[0], argv, child_env);
        _exit(127);
    }
    if (pid < 0) {
        log_line("networking: background fork failed for %s: %s", name, strerror(errno));
    } else {
        log_line("networking: started %s pid=%ld", name, (long)pid);
    }
    return pid;
}

static void ip2(const char *a, const char *b) {
    char *const argv[] = { "/System/Networking/Core/ip", (char *)a, (char *)b, 0 };
    spawn_wait(argv);
}


static void ip4(const char *a, const char *b, const char *c, const char *d) {
    char *const argv[] = { "/System/Networking/Core/ip", (char *)a, (char *)b, (char *)c, (char *)d, 0 };
    spawn_wait(argv);
}


static int open_named_log(const char *name) {
    char path[512];
    snprintf(path, sizeof(path), "/Volumes/ESP/EFI/MixtarRVS/%s", name);
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        return fd;
    }
    mkdir_one("/System/Logs");
    snprintf(path, sizeof(path), "/System/Logs/%s", name);
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
}

enum {
    COREV09_SSH_PROBE_ATTEMPTS = 45,
    COREV09_SSH_PROBE_INTERVAL_SECONDS = 2
};

static int run_ssh_probe_to_fd(int fd, const char *address) {
    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        dprintf(fd, "ssh-probe address=%s socket failed errno=%d %s\n",
                address, errno, strerror(errno));
        return 1;
    }

    struct timeval timeout;
    timeout.tv_sec = 2;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in endpoint;
    memset(&endpoint, 0, sizeof(endpoint));
    endpoint.sin_family = AF_INET;
    endpoint.sin_port = htons(22);
    if (inet_pton(AF_INET, address, &endpoint.sin_addr) != 1) {
        dprintf(fd, "ssh-probe address=%s invalid address\n", address);
        close(sock);
        return 1;
    }
    if (connect(sock, (struct sockaddr *)&endpoint, sizeof(endpoint)) != 0) {
        dprintf(fd, "ssh-probe address=%s connect failed errno=%d %s\n",
                address, errno, strerror(errno));
        close(sock);
        return 1;
    }

    char banner[256];
    ssize_t n = recv(sock, banner, sizeof(banner) - 1, 0);
    if (n <= 0) {
        dprintf(fd, "ssh-probe address=%s connected but banner failed errno=%d %s\n",
                address, errno, strerror(errno));
        close(sock);
        return 1;
    }
    banner[n] = 0;
    char *line_end = strpbrk(banner, "\r\n");
    if (line_end != 0) {
        *line_end = 0;
    }
    dprintf(fd, "ssh-probe address=%s connected banner=%s\n", address, banner);
    close(sock);
    return strncmp(banner, "SSH-", 4) == 0 ? 0 : 1;
}

static void log_sshd_processes_to_fd(int fd) {
    DIR *dir = opendir("/System/Process");
    if (!dir) {
        dprintf(fd, "sshd-processes unavailable errno=%d %s\n", errno, strerror(errno));
        return;
    }
    int found = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != 0) {
        char *end = 0;
        long pid_long = strtol(entry->d_name, &end, 10);
        if (end == entry->d_name || *end != 0 || pid_long <= 1) {
            continue;
        }
        char path[512];
        snprintf(path, sizeof(path), "/System/Process/%ld/comm", pid_long);
        int comm_fd = open(path, O_RDONLY);
        if (comm_fd < 0) {
            continue;
        }
        char comm[128];
        ssize_t n = read(comm_fd, comm, sizeof(comm) - 1);
        close(comm_fd);
        if (n <= 0) {
            continue;
        }
        comm[n] = 0;
        char *nl = strchr(comm, '\n');
        if (nl != 0) {
            *nl = 0;
        }
        if (strstr(comm, "sshd") != 0 || strstr(comm, "mixtar-sshd") != 0) {
            dprintf(fd, "sshd-process pid=%ld comm=%s\n", pid_long, comm);
            found++;
        }
    }
    closedir(dir);
    dprintf(fd, "sshd-process-count=%d\n", found);
}

static int find_native_ipv4(char *address, size_t size) {
    struct ifaddrs *all = 0;
    if (getifaddrs(&all) != 0) {
        return 0;
    }
    int found = 0;
    for (struct ifaddrs *it = all; it != 0; it = it->ifa_next) {
        if (!it->ifa_addr || it->ifa_addr->sa_family != AF_INET || strcmp(it->ifa_name, "lo") == 0) {
            continue;
        }
        const struct sockaddr_in *sin = (const struct sockaddr_in *)it->ifa_addr;
        uint32_t value = ntohl(sin->sin_addr.s_addr);
        if (value == 0 || (value >> 24) == 127 || (value & 0xffff0000U) == 0xa9fe0000U) {
            continue;
        }
        if (inet_ntop(AF_INET, &sin->sin_addr, address, size) != 0) {
            found = 1;
            break;
        }
    }
    freeifaddrs(all);
    return found;
}

static void run_ssh_selftest(void) {
    int fd = open_named_log("CoreV09-ssh-selftest.log");
    if (fd < 0) {
        log_line("networking: cannot open CoreV09-ssh-selftest.log: %s", strerror(errno));
        return;
    }
    dprintf(fd, "MixtarRVS CoreV09 SSH self-test\n");
    dprintf(fd, "port=22\n");
    int loopback_rc = 1;
    int native_rc = 1;
    int completed_attempt = 0;
    for (int attempt = 1; attempt <= COREV09_SSH_PROBE_ATTEMPTS; attempt++) {
        completed_attempt = attempt;
        dprintf(fd, "attempt=%d\n", attempt);
        log_sshd_processes_to_fd(fd);
        if (loopback_rc != 0) {
            loopback_rc = run_ssh_probe_to_fd(fd, "127.0.0.1");
        }
        if (native_rc != 0) {
            char native_address[INET_ADDRSTRLEN];
            if (find_native_ipv4(native_address, sizeof(native_address))) {
                dprintf(fd, "ssh-probe detected native address=%s\n", native_address);
                native_rc = run_ssh_probe_to_fd(fd, native_address);
            } else {
                dprintf(fd, "ssh-probe native address not available yet\n");
            }
        }
        fsync(fd);
        if (loopback_rc == 0 && native_rc == 0) {
            break;
        }
        sleep_seconds(COREV09_SSH_PROBE_INTERVAL_SECONDS);
    }
    dprintf(fd, "result loopback=%d native-address=%d attempts=%d\n",
            loopback_rc, native_rc, completed_attempt);
    fsync(fd);
    close(fd);
    log_line("networking: SSH self-test complete loopback=%d native-address=%d attempts=%d",
             loopback_rc, native_rc, completed_attempt);
}

static void spawn_ssh_selftest_watchdog(void) {
    pid_t pid = fork();
    if (pid == 0) {
        sleep_seconds(3);
        run_ssh_selftest();
        _exit(0);
    }
    if (pid > 0) {
        log_line("networking: SSH self-test watchdog pid=%ld", (long)pid);
    } else {
        log_line("networking: SSH self-test watchdog fork failed: %s", strerror(errno));
    }
}

struct mi_icmp_echo {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t id;
    uint16_t seq;
    uint8_t payload[32];
};

static uint16_t mi_checksum(const void *data, size_t len) {
    const uint8_t *bytes = (const uint8_t *)data;
    uint32_t sum = 0;
    while (len > 1) {
        sum += (uint16_t)((bytes[0] << 8) | bytes[1]);
        bytes += 2;
        len -= 2;
    }
    if (len > 0) {
        sum += (uint16_t)(bytes[0] << 8);
    }
    while ((sum >> 16) != 0) {
        sum = (sum & 0xffffu) + (sum >> 16);
    }
    return (uint16_t)(~sum);
}

static int run_icmp_probe_to_fd(int fd, const char *target) {
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (sock < 0) {
        dprintf(fd, "native-icmp target=%s socket failed errno=%d %s\n", target, errno, strerror(errno));
        return 1;
    }

    struct timeval tv;
    tv.tv_sec = 3;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in dst;
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    if (inet_pton(AF_INET, target, &dst.sin_addr) != 1) {
        dprintf(fd, "native-icmp target=%s invalid address\n", target);
        close(sock);
        return 1;
    }

    struct mi_icmp_echo pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.type = 8;
    pkt.code = 0;
    pkt.id = htons((uint16_t)(getpid() & 0xffff));
    pkt.seq = htons(1);
    memcpy(pkt.payload, "MixtarRVS-CoreV09-native-icmp", 29);
    pkt.checksum = htons(mi_checksum(&pkt, sizeof(pkt)));

    ssize_t sent = sendto(sock, &pkt, sizeof(pkt), 0, (struct sockaddr *)&dst, sizeof(dst));
    if (sent < 0) {
        dprintf(fd, "native-icmp target=%s sendto failed errno=%d %s\n", target, errno, strerror(errno));
        close(sock);
        return 1;
    }
    dprintf(fd, "native-icmp target=%s sent=%ld\n", target, (long)sent);

    uint8_t buf[1500];
    for (;;) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n < 0) {
            dprintf(fd, "native-icmp target=%s recv failed errno=%d %s\n", target, errno, strerror(errno));
            close(sock);
            return 1;
        }
        if (n < 28) {
            continue;
        }
        size_t ihl = (size_t)(buf[0] & 0x0f) * 4u;
        if (ihl < 20 || ihl + 8 > (size_t)n) {
            continue;
        }
        uint8_t type = buf[ihl];
        uint16_t id = (uint16_t)((buf[ihl + 4] << 8) | buf[ihl + 5]);
        if (type == 0 && id == (uint16_t)(getpid() & 0xffff)) {
            dprintf(fd, "native-icmp target=%s reply ok bytes=%ld\n", target, (long)n);
            close(sock);
            return 0;
        }
    }
}

static int run_udp_dns_probe_to_fd(int fd, const char *target) {
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) {
        dprintf(fd, "udp-dns target=%s socket failed errno=%d %s\n", target, errno, strerror(errno));
        return 1;
    }

    struct timeval tv;
    tv.tv_sec = 3;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in dst;
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons(53);
    if (inet_pton(AF_INET, target, &dst.sin_addr) != 1) {
        dprintf(fd, "udp-dns target=%s invalid address\n", target);
        close(sock);
        return 1;
    }

    uint8_t query[] = {
        0x4d, 0x52, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x07, 'e',  'x',  'a',
        'm',  'p',  'l',  'e',  0x03, 'c',  'o',  'm',
        0x00, 0x00, 0x01, 0x00, 0x01
    };
    ssize_t sent = sendto(sock, query, sizeof(query), 0, (struct sockaddr *)&dst, sizeof(dst));
    if (sent < 0) {
        dprintf(fd, "udp-dns target=%s sendto failed errno=%d %s\n", target, errno, strerror(errno));
        close(sock);
        return 1;
    }
    dprintf(fd, "udp-dns target=%s sent=%ld\n", target, (long)sent);

    uint8_t reply[512];
    ssize_t n = recv(sock, reply, sizeof(reply), 0);
    if (n < 0) {
        dprintf(fd, "udp-dns target=%s recv failed errno=%d %s\n", target, errno, strerror(errno));
        close(sock);
        return 1;
    }
    dprintf(fd, "udp-dns target=%s reply ok bytes=%ld\n", target, (long)n);
    close(sock);
    return 0;
}

static void run_ping_test(void) {
    int fd = open_named_log("CoreV09-ping.log");
    if (fd < 0) {
        log_line("networking: cannot open CoreV09-ping.log: %s", strerror(errno));
        return;
    }
    dprintf(fd, "MixtarRVS CoreV09 network ping test\n");
    dprintf(fd, "target=8.8.8.8\n");
    dprintf(fd, "count=4\n");
    dprintf(fd, "--- ip -br addr\n");
    char *const addr_argv[] = { "/System/Networking/Core/ip", "-br", "addr", 0 };
    spawn_wait_to_fd(addr_argv, fd);
    dprintf(fd, "--- ip route\n");
    char *const route_argv[] = { "/System/Networking/Core/ip", "route", 0 };
    spawn_wait_to_fd(route_argv, fd);
    dprintf(fd, "--- native icmp 192.168.99.254\n");
    int icmp_gateway_rc = run_icmp_probe_to_fd(fd, "192.168.99.254");
    dprintf(fd, "native-icmp-gateway.rc=%d\n", icmp_gateway_rc);
    dprintf(fd, "--- native icmp 8.8.8.8\n");
    int icmp_internet_rc = run_icmp_probe_to_fd(fd, "8.8.8.8");
    dprintf(fd, "native-icmp-internet.rc=%d\n", icmp_internet_rc);
    dprintf(fd, "--- udp dns 8.8.8.8\n");
    int dns_rc = run_udp_dns_probe_to_fd(fd, "8.8.8.8");
    dprintf(fd, "udp-dns.rc=%d\n", dns_rc);
    dprintf(fd, "--- ping -c 4 8.8.8.8\n");
    if (access("/System/Userland/ping", X_OK) != 0) {
        dprintf(fd, "ping=missing: /System/Userland/ping\n");
        fsync(fd);
        close(fd);
        return;
    }
    char *const ping_argv[] = { "/System/Userland/ping", "-c", "4", "8.8.8.8", 0 };
    int rc = spawn_wait_to_fd(ping_argv, fd);
    dprintf(fd, "ping.rc=%d\n", rc);
    fsync(fd);
    close(fd);
    log_line("networking: ping test complete rc=%d", rc);
}

static void spawn_ping_watchdog(void) {
    pid_t pid = fork();
    if (pid == 0) {
        sleep_seconds(8);
        run_ping_test();
        _exit(0);
    }
    if (pid > 0) {
        log_line("networking: ping test watchdog pid=%ld", (long)pid);
    } else {
        log_line("networking: ping test watchdog fork failed: %s", strerror(errno));
    }
}

static void log_dmesg_snapshot(void) {
    char *const argv[] = { "/System/Networking/Core/dmesg", 0 };
    log_line("networking: kernel dmesg snapshot begin");
    spawn_wait(argv);
    log_line("networking: kernel dmesg snapshot end");
}

static void log_present_ifaces(void) {
    DIR *dir = opendir("/System/Hardware/class/net");
    if (!dir) {
        log_line("networking: cannot list /System/Hardware/class/net: %s", strerror(errno));
        return;
    }
    struct dirent *entry;
    while ((entry = readdir(dir)) != 0) {
        if (entry->d_name[0] == '.') {
            continue;
        }
        log_line("networking: iface present %s", entry->d_name);
    }
    closedir(dir);
}

static int read_first_line(const char *path, char *buf, size_t size) {
    if (size == 0) {
        return 0;
    }
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        return 0;
    }
    ssize_t n = read(fd, buf, size - 1);
    close(fd);
    if (n <= 0) {
        buf[0] = 0;
        return 0;
    }
    buf[n] = 0;
    char *nl = strchr(buf, '\n');
    if (nl) {
        *nl = 0;
    }
    return 1;
}

static int iface_is_wireless(const char *iface) {
    char sys_path[512];
    snprintf(sys_path, sizeof(sys_path), "/System/Hardware/class/net/%s/wireless", iface);
    if (access(sys_path, F_OK) == 0) {
        return 1;
    }
    return strncmp(iface, "wlan", 4) == 0 || strncmp(iface, "wlp", 3) == 0;
}

static int iface_is_ready(const char *iface) {
    char sys_path[512];
    char state[64];
    snprintf(sys_path, sizeof(sys_path), "/System/Hardware/class/net/%s/operstate", iface);
    if (!read_first_line(sys_path, state, sizeof(state))) {
        return 0;
    }
    return strcmp(state, "up") == 0 || strcmp(state, "unknown") == 0;
}

static int iface_has_ipv4(const char *iface) {
    struct ifaddrs *all = 0;
    if (getifaddrs(&all) != 0) {
        return 0;
    }
    int found = 0;
    for (struct ifaddrs *it = all; it != 0; it = it->ifa_next) {
        if (!it->ifa_addr || it->ifa_addr->sa_family != AF_INET || strcmp(it->ifa_name, iface) != 0) {
            continue;
        }
        const struct sockaddr_in *sin = (const struct sockaddr_in *)it->ifa_addr;
        uint32_t address = ntohl(sin->sin_addr.s_addr);
        if (address != 0 && (address >> 24) != 127 && (address & 0xffff0000U) != 0xa9fe0000U) {
            found = 1;
            break;
        }
    }
    freeifaddrs(all);
    return found;
}

static int system_has_ipv4(void) {
    struct ifaddrs *all = 0;
    if (getifaddrs(&all) != 0) {
        return 0;
    }
    int found = 0;
    for (struct ifaddrs *it = all; it != 0; it = it->ifa_next) {
        if (!it->ifa_addr || it->ifa_addr->sa_family != AF_INET || strcmp(it->ifa_name, "lo") == 0) {
            continue;
        }
        const struct sockaddr_in *sin = (const struct sockaddr_in *)it->ifa_addr;
        uint32_t address = ntohl(sin->sin_addr.s_addr);
        if (address != 0 && (address >> 24) != 127 && (address & 0xffff0000U) != 0xa9fe0000U) {
            found = 1;
            break;
        }
    }
    freeifaddrs(all);
    return found;
}


static void bring_iface_up(const char *iface) {
    char sys_path[512];
    if (strcmp(iface, "lo") == 0) {
        return;
    }
    snprintf(sys_path, sizeof(sys_path), "/System/Hardware/class/net/%s", iface);
    if (access(sys_path, F_OK) != 0) {
        return;
    }
    ip4("link", "set", iface, "up");
}


static void configure_selected_iface(const char *iface) {
    if (iface_has_ipv4(iface)) {
        log_line("networking: existing DHCP/global IPv4 retained on %s", iface);
        return;
    }
    log_line("networking: no DHCP address on %s; static fallback disabled", iface);
}

static void configure_active_iface(void) {
    DIR *dir = opendir("/System/Hardware/class/net");
    if (!dir) {
        log_line("networking: cannot open /System/Hardware/class/net: %s", strerror(errno));
        return;
    }
    struct dirent *entry;
    char wired[256];
    char wireless[256];
    wired[0] = 0;
    wireless[0] = 0;
    while ((entry = readdir(dir)) != 0) {
        if (entry->d_name[0] == '.') {
            continue;
        }
        if (strcmp(entry->d_name, "lo") == 0) {
            continue;
        }
        bring_iface_up(entry->d_name);
        if (!iface_is_ready(entry->d_name)) {
            continue;
        }
        if (iface_is_wireless(entry->d_name)) {
            if (wireless[0] == 0) {
                snprintf(wireless, sizeof(wireless), "%s", entry->d_name);
            }
        } else if (wired[0] == 0) {
            snprintf(wired, sizeof(wired), "%s", entry->d_name);
        }
    }
    closedir(dir);

    const char *selected = wired[0] != 0 ? wired : wireless;
    if (selected[0] == 0) {
        log_line("networking: no ready non-loopback iface");
    } else {
        log_line("networking: selected iface %s", selected);
    }


    if (selected[0] != 0) {
        configure_selected_iface(selected);
    }
}

static void network_loop(void) {
    ip4("link", "set", "lo", "up");
    for (int i = 0; i < 5; i++) {
        if (system_has_ipv4()) {
            log_line("networking: existing DHCP/global IPv4 retained");
            ip2("-br", "addr");
            return;
        }
        sleep_seconds(1);
    }
    configure_active_iface();
    ip2("-br", "addr");
}

int main(void) {
    open_log();
    log_line("MixtarRVS CoreV09 networking service started");
    log_line("networking: native static service, no POSIX null dependency");
    log_present_ifaces();
    log_dmesg_snapshot();
    char *const wifi_argv[] = { "/System/Networking/WiFi/mixtar-wifi-service", 0 };
    char *const ssh_argv[] = { "/System/Networking/SSH/mixtar-sshd-service", 0 };
    spawn_background(wifi_argv, "wifi");
    spawn_ping_watchdog();
    spawn_ssh_selftest_watchdog();

    pid_t net_pid = fork();
    if (net_pid == 0) {
        network_loop();
        _exit(0);
    }
    log_line("networking: config loop pid=%ld", (long)net_pid);
    sleep_seconds(2);
    for (;;) {

        log_line("networking: exec recovery sshd wrapper");
        int rc = spawn_wait(ssh_argv);
        log_line("networking: sshd wrapper exited rc=%d", rc);

        sleep_seconds(5);
    }
}
C
    "$cc_bin" -O2 -static -Wall -Wextra -Werror -o "$service" "$src"
    chmod 0755 "$service"
}

stage_corev09_networking() {
    init_src_base="$generated_dir/ail-native-initramfs-root"
    networking_src="$init_src_base/System/Networking"
    ssh_config_src="$init_src_base/System/Configuration/SSH"

    [ -d "$networking_src/Core" ] || fail "missing generated networking core: $networking_src/Core"
    [ -d "$networking_src/WiFi" ] || fail "missing generated Wi-Fi runtime: $networking_src/WiFi"
    [ -d "$networking_src/SSH" ] || fail "missing generated OpenSSH runtime: $networking_src/SSH"
    [ -d "$ssh_config_src" ] || fail "missing generated SSH config: $ssh_config_src"

    mkdir -p "$stage_root/System/Networking" "$stage_root/System/Configuration"
    copy_tree_if_exists "$networking_src/Core" "$stage_root/System/Networking/Core" || return 1
    copy_tree_if_exists "$networking_src/WiFi" "$stage_root/System/Networking/WiFi" || return 1
    copy_tree_if_exists "$networking_src/SSH" "$stage_root/System/Networking/SSH" || return 1
    copy_tree_if_exists "$ssh_config_src" "$stage_root/System/Configuration/SSH" || return 1
    sed -i '/^[[:space:]]*UsePAM[[:space:]]/d' "$stage_root/System/Configuration/SSH/sshd_config"
    if ! grep -Fqx 'ChrootDirectory /Native' "$stage_root/System/Configuration/SSH/sshd_config"; then
        printf '\nChrootDirectory /Native\n' >> "$stage_root/System/Configuration/SSH/sshd_config"
    fi
    sed -i '/^[[:space:]]*SetEnv[[:space:]]\+PATH=/d' "$stage_root/System/Configuration/SSH/sshd_config"
    printf 'SetEnv PATH=/System/Shells:/System/Userland\n' >> "$stage_root/System/Configuration/SSH/sshd_config"
    chmod 0700 "$stage_root/System/Configuration/SSH/HostKeys" || true
    chmod 0600 "$stage_root/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key" || true
    chmod 0644 "$stage_root/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key.pub" || true
    chmod 0644 "$stage_root/System/Configuration/SSH/sshd_config" "$stage_root/System/Configuration/SSH/SSH.config" "$stage_root/System/Configuration/SSH/moduli" 2>/dev/null || true
    mkdir -p "$stage_root/System/Networking/WiFi/Root/etc"
    cat > "$stage_root/System/Networking/WiFi/Root/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/sbin/nologin
EOF
    cat > "$stage_root/System/Networking/WiFi/Root/etc/group" <<'EOF'
root:x:0:
EOF

    for script in ip mount umount dmesg dhcpcd; do
        rewrite_networking_script_runtime "$stage_root/System/Networking/Core/$script"
    done
    if [ -f "$stage_root/System/Networking/SSH/Root/etc/passwd" ]; then
        sed -i \
            -e 's#/System/Terminal/ZSH/start-zsh#/System/Shells/zsh#g' \
            -e 's#/System/Terminal/ZSH/zsh#/System/Shells/zsh#g' \
            "$stage_root/System/Networking/SSH/Root/etc/passwd"
    fi
    write_corev09_networking_service
    build_corev09_sshd_service
    note "staged CoreV09 recovery networking and SSH"
}

copy_host_runtime_lib() {
    lib_name=$1
    dst_dir="$stage_root/System/Shells/Runtime"
    dst="$dst_dir/$lib_name"

    [ -e "$dst" ] && return 0
    command -v ldconfig >/dev/null 2>&1 || return 1

    src=$(ldconfig -p 2>/dev/null | awk -v lib="$lib_name" '$1 == lib { print $NF; exit }')
    [ -n "$src" ] || return 1
    [ -f "$src" ] || return 1

    mkdir -p "$dst_dir"
    cp -L "$src" "$dst"
    chmod 0644 "$dst" || true
    copy_needed_runtime_libs "$dst"
    note "copied runtime library $lib_name -> /System/Shells/Runtime"
    return 0
}

copy_needed_runtime_libs() {
    binary=$1
    [ -f "$binary" ] || return 0
    command -v readelf >/dev/null 2>&1 || return 0

    needed=$(readelf -d "$binary" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
    for lib in $needed; do
        if [ -e "$stage_root/System/Shells/Runtime/$lib" ] || [ -e "$stage_root/System/Libraries/$lib" ]; then
            continue
        fi
        copy_host_runtime_lib "$lib" || fail "missing runtime library for $(basename -- "$binary"): $lib"
    done
}

stage_corev09_executor() {
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    repo_root="$(cd "$script_dir/../../.." && pwd)"
    ailang_root="${AILANG_ROOT:-$repo_root/../AILang}"
    executor_ail_src="$script_dir/../../Runtime/Executor/mixtar_executor.ail"
    executor_dst="$stage_root/System/Runtime/Executor"
    executor_interp="$stage_root/System/Shells/Runtime/ld-linux-x86-64.so.2"

    [ -f "$executor_ail_src" ] || fail "missing AILang executor source: $executor_ail_src"
    [ -f "$ailang_root/ailang.py" ] || fail "missing AILang toolchain: $ailang_root/ailang.py"

    if python3 "$ailang_root/ailang.py" "$executor_ail_src" --check &&
       python3 "$ailang_root/ailang.py" "$executor_ail_src" --backend=c -o "$executor_dst"; then
        chmod 0755 "$executor_dst"
        if [ -f "$executor_interp" ] && command -v patchelf >/dev/null 2>&1; then
            patchelf --set-interpreter /System/Shells/Runtime/ld-linux-x86-64.so.2 "$executor_dst"
            patchelf --force-rpath --set-rpath /System/Shells/Runtime "$executor_dst"
        fi
        copy_needed_runtime_libs "$executor_dst"
        note "staged AILang /System/Runtime/Executor"
        return 0
    fi

    fail "failed to build AILang /System/Runtime/Executor"
}

stage_corev09_pid1() {
    ailang_root="${AILANG_ROOT:-$repo_root/../AILang}"
    init_src="$rootfs_dir/initramfs/mixtar_init.ail"
    sqlite_pid1_dir="$generated_dir/sqlite-pid1"
    sqlite_pid1_c="${MIXTAR_PID1_SQLITE_C:-$sqlite_pid1_dir/sqlite3.c}"
    sqlite_pid1_o="$sqlite_pid1_dir/sqlite3-corev09.o"
    generated_c="$generated_dir/corev09-mixtar-init.c"
    pid1_dst="$stage_root/System/Init/MixtarRVS"
    cc_bin="${CC:-}"

    if [ -z "$cc_bin" ]; then
        if command -v musl-gcc >/dev/null 2>&1; then
            cc_bin="musl-gcc"
        else
            cc_bin="cc"
        fi
    fi

    [ -f "$init_src" ] || fail "missing AILang PID1 source: $init_src"
    [ -f "$ailang_root/ailang.py" ] || fail "missing AILang toolchain: $ailang_root/ailang.py"
    [ -f "$sqlite_pid1_c" ] || fail "missing local PID1 SQLite amalgamation: $sqlite_pid1_c"
    command -v "$cc_bin" >/dev/null 2>&1 || fail "missing PID1 compiler: $cc_bin"

    mkdir -p "$sqlite_pid1_dir" "$(dirname -- "$pid1_dst")"

    python3 "$ailang_root/ailang.py" "$init_src" --check
    python3 "$ailang_root/ailang.py" "$init_src" --effect-policy
    python3 "$ailang_root/ailang.py" "$init_src" --emit-c -o "$generated_c"

    "$cc_bin" \
        -O2 \
        -DSQLITE_OMIT_LOAD_EXTENSION=1 \
        -DSQLITE_THREADSAFE=0 \
        -DSQLITE_DEFAULT_MEMSTATUS=0 \
        -DSQLITE_DQS=0 \
        -DSQLITE_OMIT_DEPRECATED=1 \
        -DSQLITE_OMIT_SHARED_CACHE=1 \
        -I"$sqlite_pid1_dir" \
        -c "$sqlite_pid1_c" \
        -o "$sqlite_pid1_o"

    "$cc_bin" \
        -O2 \
        -static \
        -ffunction-sections \
        -fdata-sections \
        -Wl,--gc-sections \
        -DAILANG_TRACK_ALLOCATIONS=0 \
        -DNDEBUG \
        -Wall \
        -Wextra \
        -Werror \
        -I"$sqlite_pid1_dir" \
        -o "$pid1_dst" \
        "$generated_c" \
        "$sqlite_pid1_o" \
        -lm

    chmod 0755 "$pid1_dst"
    if command -v strip >/dev/null 2>&1; then
        strip "$pid1_dst" 2>/dev/null || true
    fi

    if strings -a "$pid1_dst" | grep -F "PATH=/System/Tools" >/dev/null 2>&1 ||
       strings -a "$pid1_dst" | grep -F "/System/Tools/" >/dev/null 2>&1; then
        fail "rebuilt PID1 still contains old /System/Tools paths"
    fi
    if ! strings -a "$pid1_dst" | grep -F "PATH=/System/Userland" >/dev/null 2>&1 ||
       ! strings -a "$pid1_dst" | grep -F "/System/Userland/" >/dev/null 2>&1; then
        fail "rebuilt PID1 does not contain /System/Userland paths"
    fi

    note "rebuilt AILang PID1 -> /System/Init/MixtarRVS"
}

write_driver_store() {
    driver_dir="$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION"
    mkdir -p "$driver_dir" "$stage_root/System/Drivers"
    python3 - "$driver_dir" "$KERNEL_VERSION" "$VERSION" "$kernel_config" "$modules_builtin" <<'PY'
import pathlib
import sqlite3
import sys

driver_dir = pathlib.Path(sys.argv[1])
kernel_version = sys.argv[2]
system_version = sys.argv[3]
kernel_config = pathlib.Path(sys.argv[4])
modules_builtin = pathlib.Path(sys.argv[5])

def load_config(path):
    values = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if raw.startswith("CONFIG_") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value.strip('"')
        elif raw.startswith("# CONFIG_") and raw.endswith(" is not set"):
            key = raw[2:].split(" ", 1)[0]
            values[key] = "n"
    return values

cfg = load_config(kernel_config)
builtins = []
if modules_builtin.is_file():
    builtins = [line.strip() for line in modules_builtin.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip()]

declared = [
    ("efi", "boot-required", "CONFIG_EFI", "UEFI firmware interface"),
    ("efi-stub", "boot-required", "CONFIG_EFI_STUB", "single MixtarRVS EFI artifact"),
    ("initramfs", "boot-required", "CONFIG_BLK_DEV_INITRD", "embedded clean-root initramfs"),
    ("tmpfs", "boot-required", "CONFIG_TMPFS", "runtime and Temporary mounts"),
    ("procfs", "boot-required", "CONFIG_PROC_FS", "/System/Process kernel view"),
    ("sysfs", "boot-required", "CONFIG_SYSFS", "/System/Hardware kernel view"),
    ("devtmpfs", "boot-required", "CONFIG_DEVTMPFS", "/System/Devices runtime device view"),
    ("unix-sockets", "boot-required", "CONFIG_UNIX", "local service sockets"),
    ("pty", "boot-required", "CONFIG_UNIX98_PTYS", "interactive shell sessions"),
    ("vt-console", "boot-required", "CONFIG_VT_CONSOLE", "local console"),
    ("nvme", "hardware-present", "CONFIG_BLK_DEV_NVME", "ThinkPad internal NVMe storage"),
    ("ext4", "hardware-present", "CONFIG_EXT4_FS", "local Linux root/data filesystem"),
    ("usb-xhci", "hardware-present", "CONFIG_USB_XHCI_HCD", "USB controller"),
    ("usb-hid", "hardware-present", "CONFIG_USB_HID", "USB keyboard/mouse"),
    ("at-keyboard", "hardware-present", "CONFIG_KEYBOARD_ATKBD", "ThinkPad keyboard"),
    ("ps2-mouse", "hardware-present", "CONFIG_MOUSE_PS2", "ThinkPad trackpoint/touchpad path"),
    ("intel-ethernet-e1000e", "hardware-present", "CONFIG_E1000E", "Intel wired network"),
    ("intel-wifi", "hardware-present", "CONFIG_IWLWIFI", "Intel Wi-Fi driver family"),
    ("intel-wifi-mvm", "hardware-present", "CONFIG_IWLMVM", "Intel Wi-Fi MVM firmware path"),
    ("intel-drm-i915", "blocked", "CONFIG_DRM_I915", "blocked by Linux 7.1.2 PREEMPT_RT dependency: DRM_I915 depends on !PREEMPT_RT"),
    ("vfat", "optional-local", "CONFIG_VFAT_FS", "EFI/FAT volume access"),
    ("ahci", "optional-local", "CONFIG_SATA_AHCI", "SATA fallback storage"),
    ("seccomp", "optional-local", "CONFIG_SECCOMP_FILTER", "service isolation"),
    ("landlock", "optional-local", "CONFIG_SECURITY_LANDLOCK", "filesystem restriction layer"),
    ("namespaces", "optional-local", "CONFIG_NAMESPACES", "compatibility/runtime isolation"),
    ("bpf", "optional-local", "CONFIG_BPF_SYSCALL", "diagnostics and future filtering"),
]

policies = [
    ("root.device_namespace", "/System/Devices"),
    ("root.no_dev_path", "true"),
    ("root.no_etc_path", "true"),
    ("root.no_bin_path", "true"),
    ("root.no_usr_path", "true"),
    ("devtmpfs.automount", "disabled"),
    ("distro.coldplug", "disabled"),
    ("module.autoload", "disabled-for-v0"),
    ("driver.source", "linux-kernel-config"),
]

db_path = driver_dir / "Drivers.config"
if db_path.exists():
    db_path.unlink()
db = sqlite3.connect(db_path)
db.executescript(
    """
    PRAGMA page_size=1024;
    PRAGMA journal_mode=OFF;
    PRAGMA synchronous=OFF;
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE policy(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE driver(
        name TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        kconfig TEXT NOT NULL,
        state TEXT NOT NULL,
        built TEXT NOT NULL,
        note TEXT NOT NULL
    );
    CREATE TABLE builtin_module(path TEXT PRIMARY KEY);
    """
)
db.executemany(
    "INSERT INTO meta(key, value) VALUES (?, ?)",
    [
        ("system", "MixtarRVS"),
        ("system.version", system_version),
        ("kernel.family", "Linux"),
        ("kernel.profile", "RT"),
        ("kernel.version", kernel_version),
        ("kernel.layout", f"/System/Kernel/Linux/RT/{kernel_version}"),
        ("config.source", str(kernel_config)),
        ("modules.builtin.source", str(modules_builtin)),
    ],
)
db.executemany("INSERT INTO policy(key, value) VALUES (?, ?)", policies)
rows = []
for name, category, key, note in declared:
    value = cfg.get(key, "missing")
    state = "blocked" if category == "blocked" else ("enabled" if value in {"y", "m"} else "missing")
    rows.append((name, category, key, state, value, note))
db.executemany("INSERT INTO driver(name, category, kconfig, state, built, note) VALUES (?, ?, ?, ?, ?, ?)", rows)
db.executemany("INSERT INTO builtin_module(path) VALUES (?)", [(item,) for item in builtins])
db.execute("PRAGMA user_version=1")
db.commit()
db.execute("VACUUM")
db.close()

enabled = sum(1 for row in rows if row[3] == "enabled")
blocked = [row for row in rows if row[3] == "blocked"]
missing = [row for row in rows if row[3] == "missing"]
status_lines = [
    "MixtarRVS Driver Store v0",
    f"system.version={system_version}",
    f"kernel=Linux/RT/{kernel_version}",
    f"layout=/System/Drivers/Linux/RT/{kernel_version}",
    "device.namespace=/System/Devices",
    "policy.no_visible_dev=true",
    "policy.no_visible_etc=true",
    "policy.no_visible_bin=true",
    "policy.devtmpfs_automount=disabled",
    "policy.distro_coldplug=disabled",
    f"declared_drivers={len(rows)}",
    f"enabled_drivers={enabled}",
    f"blocked_drivers={len(blocked)}",
    f"missing_drivers={len(missing)}",
    f"builtin_modules={len(builtins)}",
    "",
]
for category in ["boot-required", "hardware-present", "optional-local"]:
    status_lines.append(f"[{category}]")
    for name, row_category, key, state, built, note in rows:
        if row_category == category:
            status_lines.append(f"{name}: {state} {key}={built} - {note}")
    status_lines.append("")
status_lines.append("[blocked]")
status_lines.append("/dev automount: blocked")
status_lines.append("distro coldplug: blocked")
status_lines.append("module autoload policy: blocked-for-v0")
for name, category, key, state, built, note in rows:
    if category == "blocked":
        status_lines.append(f"{name}: {state} {key}={built} - {note}")
for name, _category, key, _state, built, note in missing:
    if _category != "blocked":
        status_lines.append(f"{name}: missing {key}={built} - {note}")
(driver_dir / "Drivers.status").write_text("\n".join(status_lines) + "\n", encoding="utf-8")
PY

}

write_config_seed() {
    dst="$stage_root/System/Configuration/MixtarRVS.config.sql"
    cat > "$dst" <<EOF
create table if not exists system_profile (
    key text primary key,
    value text not null
);

insert or replace into system_profile(key, value) values
('name', 'MixtarRVS'),
('version', '$VERSION'),
('kernel.family', 'Linux'),
('kernel.profile', 'RT'),
('kernel.version', '$KERNEL_VERSION'),
('kernel.layout', '/System/Kernel/Linux/RT/$KERNEL_VERSION'),
('boot.mode', 'single-uki'),
('boot.artifact', '/System/EFI/MixtarRVS/$VERSION.efi'),
('init.pid1', '/System/Init/MixtarRVS'),
('shell.default', '/System/Shells/zsh'),
('runtime.executor', '/System/Runtime/Executor'),
('runtime.executor.source', 'AILang'),
('security.path', '/System/Security'),
('security.policy', '/System/Configuration/Security/Policy.config'),
('security.runtime', '/System/Runtime/Security'),
('admin.mode', 'session-token'),
('admin.command', 'admin'),
('sudo.default', 'false'),
('debian.policy', 'build-rescue-only');

create table if not exists native_root (
    path text primary key
);

insert or replace into native_root(path) values
('/Applications'),
('/System'),
('/Users'),
('/Volumes'),
('/Temporary');

create table if not exists compatibility_root (
    name text primary key,
    path text not null
);

insert or replace into compatibility_root(name, path) values
('POSIX', '/System/Compatibility/POSIX'),
('Linux', '/System/Compatibility/POSIX/Linux'),
('OpenBSD', '/System/Compatibility/POSIX/OpenBSD'),
('FreeBSD', '/System/Compatibility/POSIX/FreeBSD');
EOF
}

write_contract_marker() {
    dst="$stage_root/System/Configuration/CoreV09.contract"
    cat > "$dst" <<EOF
version=$VERSION
kernel_layout=/System/Kernel/Linux/RT/$KERNEL_VERSION
boot_mode=single-uki
boot_artifact=/System/EFI/MixtarRVS/$VERSION.efi
pid1=/System/Init/MixtarRVS
shell=/System/Shells/zsh
executor=/System/Runtime/Executor
executor_source=AILang
executor_source_path=System/Runtime/Executor/mixtar_executor.ail
debian=build-rescue-only
stage_scope=generated-only
boot_deploy=disabled
efi_mutation=disabled
native_config=/System/Configuration
native_config_mode=sqlite-primary
native_applications=/Applications
native_applications_mode=user-visible-only
native_tools=/System/Tools
native_tools_mode=admin-only
native_userland=/System/Userland
native_userland_mode=command-root
native_drivers=/System/Drivers
native_drivers_mode=store-only
security=/System/Security
security_policy=/System/Configuration/Security/Policy.config
security_runtime=/System/Runtime/Security
admin_mode=session-token
admin_command=admin
sudo_default=false
posix=/System/Compatibility
EOF
}

write_networking_config() {
    config_dir="$stage_root/System/Configuration/Networking"
    mkdir -p "$config_dir"
    python3 - "$config_dir" <<'PY'
import pathlib
import sqlite3
import sys

config_dir = pathlib.Path(sys.argv[1])

def write_db(name, rows, user_version):
    db_path = config_dir / name
    if db_path.exists():
        db_path.unlink()
    db = sqlite3.connect(db_path)
    db.executescript(
        """
        PRAGMA page_size=1024;
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
    db.executemany("INSERT INTO meta(key, value) VALUES (?, ?)", rows)
    db.execute(f"PRAGMA user_version={user_version}")
    db.commit()
    db.execute("VACUUM")
    db.close()

write_db(
    "Networking.config",
    [
        ("networking.mode", "recovery-corev09"),
        ("networking.service", "/System/Networking/start-networking"),
    ("networking.ping.group_range.path", "/System/Process/sys/net/ipv4/ping_group_range"),
    ("networking.ping.gid.min", "0"),
    ("networking.ping.gid.max", "1000"),
        ("networking.address", "192.168.99.110/24"),
        ("networking.gateway", "192.168.99.254"),
        ("networking.sshd", "/System/Networking/SSH/mixtar-sshd-service"),
        ("networking.ui", "false"),
        ("networking.admin_tools", "false"),
        ("regulatory.db", "embedded"),
        ("regulatory.mode", "kernel-extra-firmware"),
    ],
    6,
)
write_db(
    "WiFi.config",
    [
        ("wifi.mode", "recovery-corev09"),
        ("wifi.backend", "iwd"),
        ("wifi.driver", "iwlwifi"),
        ("wifi.interface", "wlan0"),
        ("wifi.address", "192.168.99.110/24"),
        ("wifi.regulatory_db", "embedded"),
        ("wifi.credentials", "not-stored"),
        ("wifi.ui", "false"),
    ],
    6,
)
PY
}

write_security_config() {
    config_dir="$stage_root/System/Configuration/Security"
    auth_dir="$stage_root/System/Security"
    mkdir -p "$config_dir" "$auth_dir"
}

write_pid1_config() {
    mkdir -p "$stage_root/System/Configuration"
}

write_kernel_profile() {
    dst="$stage_root/System/Kernel/Linux/RT/$KERNEL_VERSION/kernel-profile.json"
    if [ -f "$kernel_profile_source" ]; then
        cp "$kernel_profile_source" "$dst"
    else
        cat > "$dst" <<EOF
{
  "name": "MixtarRVS CoreV09 RT kernel profile",
  "version": "$VERSION",
  "kernel": {
    "family": "Linux",
    "profile": "RT",
    "version": "$KERNEL_VERSION",
    "layout": "/System/Kernel/Linux/RT/$KERNEL_VERSION"
  },
  "boot": {
    "mode": "single-uki",
    "artifact": "/System/EFI/MixtarRVS/$VERSION.efi"
  }
}
EOF
    fi
}

stage_layout() {
    mkdir -p \
        "$stage_root/Applications" \
        "$stage_root/System/Init" \
        "$stage_root/System/Kernel/Linux/RT/$KERNEL_VERSION" \
        "$stage_root/System/EFI/MixtarRVS" \
        "$stage_root/System/Shells" \
        "$stage_root/System/Shells/Runtime" \
        "$stage_root/System/Shells/Terminfo" \
        "$stage_root/System/Tools" \
        "$stage_root/System/Userland" \
        "$stage_root/System/Drivers/Linux/RT/$KERNEL_VERSION" \
        "$stage_root/System/Libraries" \
        "$stage_root/System/Configuration" \
        "$stage_root/System/Configuration/Networking" \
        "$stage_root/System/Configuration/Security" \
        "$stage_root/System/Resources" \
        "$stage_root/System/Logs" \
        "$stage_root/System/Networking/Core/Runtime" \
        "$stage_root/System/Networking/WiFi/Runtime" \
        "$stage_root/System/Networking/WiFi/bin" \
        "$stage_root/System/Networking/WiFi/Root" \
        "$stage_root/System/Networking/SSH/Runtime" \
        "$stage_root/System/Networking/SSH/bin" \
        "$stage_root/System/Networking/SSH/sbin" \
        "$stage_root/System/Networking/SSH/libexec" \
        "$stage_root/System/Networking/SSH/Root" \
        "$stage_root/System/Devices" \
        "$stage_root/System/Devices/pts" \
        "$stage_root/System/Process" \
        "$stage_root/System/Hardware" \
        "$stage_root/System/Runtime/Devices" \
        "$stage_root/System/Runtime/Display" \
        "$stage_root/System/Runtime/Kernel/proc" \
        "$stage_root/System/Runtime/Kernel/sys" \
        "$stage_root/System/Runtime/Networking/WiFi" \
        "$stage_root/System/Runtime/Networking/SSH" \
        "$stage_root/System/Runtime/Security/Tokens" \
        "$stage_root/System/Runtime/Sessions" \
        "$stage_root/System/Runtime/Sockets" \
        "$stage_root/System/Security/Auth" \
        "$stage_root/System/Compatibility/POSIX/Linux" \
        "$stage_root/System/Compatibility/POSIX/OpenBSD" \
        "$stage_root/System/Compatibility/POSIX/FreeBSD" \
        "$stage_root/Users" \
        "$stage_root/Volumes" \
        "$stage_root/Temporary" \
        "$efi_stage/EFI/MixtarRVS"
}

stage_existing_artifacts() {
    init_src_base="$generated_dir/ail-native-initramfs-root"

    stage_corev09_pid1

    copy_if_exists "$init_src_base/System/Shells/zsh" "$stage_root/System/Shells/zsh" ||
    copy_if_exists "$init_src_base/System/Terminal/ZSH/zsh" "$stage_root/System/Shells/zsh" ||
    note "missing zsh artifact; expected /System/Shells/zsh"
    patch_corev09_zsh_runtime
    stage_corev09_executor

    copy_tree_if_exists "$init_src_base/System/Userland" "$stage_root/System/Userland" ||
    fail "missing generated userland; expected $init_src_base/System/Userland"
    copy_if_exists "$init_src_base/System/Terminal/ZSH/reboot" "$stage_root/System/Userland/reboot" ||
    fail "missing static lifecycle helper: reboot"
    copy_if_exists "$init_src_base/System/Terminal/ZSH/poweroff" "$stage_root/System/Userland/poweroff" ||
    fail "missing static lifecycle helper: poweroff"
    # Keep userland free of compiler/toolchain binaries that should live in /System/Compilers.
    rm -f "$stage_root/System/Userland/m4" "$stage_root/System/Userland/nm"
    rm -f "$stage_root/System/Tools/m4" "$stage_root/System/Tools/nm"
    write_native_ping
    write_corev09_foundation

    copy_tree_if_exists "$init_src_base/System/Libraries" "$stage_root/System/Libraries" || true
    copy_tree_if_exists "$init_src_base/System/Resources" "$stage_root/System/Resources" || true
    stage_corev09_networking


    if [ -n "$efi_source" ] && [ -f "$efi_source" ]; then
        provenance_source="$efi_source.provenance"
        [ -s "$provenance_source" ] || fail "EFI provenance missing: $provenance_source"
        cp "$efi_source" "$stage_root/System/EFI/MixtarRVS/$VERSION.efi"
        cp "$efi_source" "$efi_stage/EFI/MixtarRVS/$VERSION.efi"
        cp "$provenance_source" "$stage_root/System/EFI/MixtarRVS/$VERSION.efi.provenance"
        cp "$provenance_source" "$efi_stage/EFI/MixtarRVS/$VERSION.efi.provenance"
        note "copied EFI source -> CoreV09 $VERSION.efi"
        note "copied EFI provenance -> CoreV09 $VERSION.efi.provenance"
    elif [ "$explicit_efi_source" -ne 0 ]; then
        fail "explicit EFI source does not exist: $efi_source"
    else
        note "missing EFI source; verifier will fail until /System/EFI/MixtarRVS/$VERSION.efi exists"
        note "expected EFI source: $efi_source"
    fi
}

plan() {
    cat <<EOF
CoreV09 staging plan:
  repo:       $repo_root
  root:       $stage_root
  efi-stage:  $efi_stage
  version:    $VERSION
  kernel:     /System/Kernel/Linux/RT/$KERNEL_VERSION
  pid1:       /System/Init/MixtarRVS
  shell:      /System/Shells/zsh
  efi:        /System/EFI/MixtarRVS/$VERSION.efi
  scope:      generated-only
  boot:       disabled
  efi-write:  disabled

No Debian mutation:
  not an installer
  not a deployment tool
  no Debian package manager use
  no bootloader writes
  no EFI variable writes
  no /boot/efi writes
  no live / writes
EOF
}

write_admin_command_stubs() {
    admin_cmd="$stage_root/System/Userland/admin"
    exit_cmd="$stage_root/System/Userland/exit-admin"
    mkdir -p "$stage_root/System/Userland"
    cat > "$admin_cmd" <<'ZSH'
#!/System/Shells/zsh
print -r -- "Administrator Mode foundation is present."
print -r -- "Policy: /System/Configuration/Security/Policy.config"
print -r -- "Auth: /System/Security/Auth"
print -r -- "Runtime tokens: /System/Runtime/Security/Tokens"
print -r -- "Elevation is fail-closed until interactive approval/UI is implemented."
exit 77
ZSH
    cat > "$exit_cmd" <<'ZSH'
#!/System/Shells/zsh
print -r -- "No elevated Administrator session is active."
exit 0
ZSH
    chmod 0755 "$admin_cmd" "$exit_cmd"
}

write_native_ping() {
    ping_src="$stage_root/System/Userland/.mixtar-ping.c"
    ping_out="$stage_root/System/Userland/ping"
    mkdir -p "$stage_root/System/Userland"
    cat > "$ping_src" <<'C'
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

struct mi_icmp_echo {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t id;
    uint16_t seq;
    uint8_t payload[32];
};

static uint16_t mi_checksum(const void *data, size_t len) {
    const uint8_t *p = (const uint8_t *)data;
    uint32_t sum = 0;
    while (len > 1) {
        sum += (uint16_t)((p[0] << 8) | p[1]);
        p += 2;
        len -= 2;
    }
    if (len) {
        sum += (uint16_t)(p[0] << 8);
    }
    while (sum >> 16) {
        sum = (sum & 0xffffu) + (sum >> 16);
    }
    return (uint16_t)(~sum);
}

static int parse_count(int argc, char **argv, const char **target) {
    int count = 4;
    *target = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            count = atoi(argv[++i]);
            if (count < 1) {
                count = 1;
            }
            if (count > 64) {
                count = 64;
            }
        } else if (argv[i][0] != '-') {
            *target = argv[i];
        }
    }
    return count;
}

static int send_ping(int sock, const struct sockaddr_in *dst, uint16_t id, uint16_t seq) {
    struct mi_icmp_echo pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.type = 8;
    pkt.code = 0;
    pkt.id = htons(id);
    pkt.seq = htons(seq);
    memcpy(pkt.payload, "MixtarRVS-native-ping", 21);
    pkt.checksum = htons(mi_checksum(&pkt, sizeof(pkt)));
    ssize_t sent = sendto(sock, &pkt, sizeof(pkt), 0, (const struct sockaddr *)dst, sizeof(*dst));
    if (sent < 0) {
        fprintf(stderr, "ping: sendto: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}

static int receive_reply(int sock, const char *target, uint16_t seq) {
    uint8_t buf[1500];
    for (;;) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n < 0) {
            fprintf(stderr, "ping: recv: %s\n", strerror(errno));
            return 1;
        }
        if (n < 8) {
            continue;
        }
        uint8_t type = buf[0];
        uint16_t rx_seq = (uint16_t)((buf[6] << 8) | buf[7]);
        if (type == 0 && rx_seq == seq) {
            printf("%ld bytes from %s: icmp_seq=%u\n", (long)n, target, (unsigned)seq);
            return 0;
        }
    }
}

int main(int argc, char **argv) {
    const char *target = 0;
    int count = parse_count(argc, argv, &target);
    if (!target) {
        fprintf(stderr, "usage: ping [-c count] IPv4-address\n");
        return 2;
    }

    struct sockaddr_in dst;
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    if (inet_pton(AF_INET, target, &dst.sin_addr) != 1) {
        fprintf(stderr, "ping: only numeric IPv4 targets are supported now: %s\n", target);
        return 2;
    }

    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (sock < 0) {
        fprintf(stderr, "ping: socket: %s\n", strerror(errno));
        return 1;
    }

    struct timeval tv;
    tv.tv_sec = 3;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    uint16_t id = (uint16_t)(getpid() & 0xffff);
    int received = 0;
    printf("PING %s: %d MixtarRVS native probe(s)\n", target, count);
    for (int i = 1; i <= count; i++) {
        if (send_ping(sock, &dst, id, (uint16_t)i) == 0 &&
            receive_reply(sock, target, (uint16_t)i) == 0) {
            received++;
        }
        if (i != count) {
            sleep(1);
        }
    }
    close(sock);
    printf("--- %s ping statistics ---\n", target);
    printf("%d packets transmitted, %d packets received\n", count, received);
    return received > 0 ? 0 : 1;
}
C
    if command -v musl-gcc >/dev/null 2>&1; then
        musl-gcc -static -O2 -Wall -Wextra "$ping_src" -o "$ping_out"
    else
        cc -static -O2 -Wall -Wextra "$ping_src" -o "$ping_out"
    fi
    rm -f "$ping_src"
    chmod 0755 "$ping_out"
    note "installed native Mixtar ping -> /System/Userland/ping"
}

write_corev09_foundation() {
    mkdir -p \
        "$stage_root/System/Configuration/System" \
        "$stage_root/System/Configuration/Updates" \
        "$stage_root/System/Runtime/System" \
        "$stage_root/System/Runtime/Updates" \
        "$stage_root/System/Userland"

    cat > "$stage_root/System/Userland/network" <<'ZSH'
#!/System/Shells/zsh
PATH=/System/Networking/Core:/System/Shells:/System/Userland
export PATH
LD_LIBRARY_PATH=/System/Networking/Core/Runtime:/System/Shells/Runtime
export LD_LIBRARY_PATH
TERM=${TERM:-linux}
export TERM

cmd=${1:-status}
target=${2:-8.8.8.8}

case "$cmd" in
  status)
    print -r -- "Network"
    if [[ -x /System/Networking/Core/ip ]]; then
      print -r -- "  Interfaces:"
      /System/Networking/Core/ip -br addr
      print -r -- "  Routes:"
      /System/Networking/Core/ip route
    else
      print -r -- "  Core: unavailable"
      exit 1
    fi
    ;;
  test)
    print -r -- "Network test"
    print -r -- "  Target: $target"
    /System/Userland/ping -c 4 "$target"
    ;;
  logs)
    print -r -- "Network logs"
    if [[ -r /System/Runtime/Networking/networking.log ]]; then
      /System/Userland/cat /System/Runtime/Networking/networking.log
    else
      print -r -- "  No runtime networking log available."
    fi
    ;;
  *)
    print -r -- "usage: network [status|test|logs] [target]"
    exit 2
    ;;
esac
ZSH

    cat > "$stage_root/System/Userland/security" <<'ZSH'
#!/System/Shells/zsh
PATH=/System/Shells:/System/Userland
export PATH
LD_LIBRARY_PATH=/System/Shells/Runtime
export LD_LIBRARY_PATH

cmd=${1:-status}

case "$cmd" in
  status)
    print -r -- "Security: Normal"
    print -r -- "  Administrator Mode: fail-closed"
    print -r -- "  sudo default: disabled"
    print -r -- "  Recovery SSH: key-only target"
    print -r -- "  APX sandbox: not enforced yet"
    ;;
  details)
    print -r -- "Security details"
    print -r -- "  Policy: /System/Configuration/Security/Policy.config"
    print -r -- "  Authority: /System/Security"
    print -r -- "  Runtime: /System/Runtime/Security"
    print -r -- "  Highest is reserved for signed boot, immutable system, APX sandbox, audit, and service isolation."
    ;;
  *)
    print -r -- "usage: security [status|details]"
    exit 2
    ;;
esac
ZSH

    cat > "$stage_root/System/Userland/updates" <<'ZSH'
#!/System/Shells/zsh
PATH=/System/Shells:/System/Userland
export PATH
LD_LIBRARY_PATH=/System/Shells/Runtime
export LD_LIBRARY_PATH

cmd=${1:-status}

case "$cmd" in
  status)
    print -r -- "Updates: Unknown"
    print -r -- "  Kernel: not checked"
    print -r -- "  Userland: not checked"
    print -r -- "  Shell: not checked"
    print -r -- "  Runtime: not checked"
    print -r -- "  Reason: CoreV09 defines status plumbing; upstream checking is later."
    ;;
  sources)
    print -r -- "Update sources"
    print -r -- "  Kernel: /System/Kernel/Linux/RT"
    print -r -- "  Userland: OpenBSD-first source manifest"
    print -r -- "  Fallback: FreeBSD source manifest"
    print -r -- "  Shell: zsh upstream"
    print -r -- "  Runtime: AILang/Mixtar runtime"
    ;;
  *)
    print -r -- "usage: updates [status|sources]"
    exit 2
    ;;
esac
ZSH

    cat > "$stage_root/System/Userland/system" <<'ZSH'
#!/System/Shells/zsh
PATH=/System/Networking/Core:/System/Shells:/System/Userland
export PATH
LD_LIBRARY_PATH=/System/Networking/Core/Runtime:/System/Shells/Runtime
export LD_LIBRARY_PATH

cmd=${1:-status}

case "$cmd" in
  status)
    print -r -- "MixtarRVS CoreV09"
    print -r -- "  UI: pending"
    print -r -- "  Root: native"
    print -r -- "  Userland: /System/Userland"
    print -r -- "  Shell: /System/Shells/zsh"
    print -r -- "  Executor: /System/Runtime/Executor"
    print -r -- "  Kernel: /System/Kernel/Linux/RT/7.1.2"
    print -r -- ""
    /System/Userland/security status
    print -r -- ""
    /System/Userland/updates status
    print -r -- ""
    /System/Userland/network status
    ;;
  about)
    print -r -- "MixtarRVS CoreV09 is the no-UI foundation for MixtarRVS 1.0."
    print -r -- "It exposes simple status commands now and is intended to feed the future UI directly."
    ;;
  *)
    print -r -- "usage: system [status|about]"
    exit 2
    ;;
esac
ZSH

    chmod 0755 \
        "$stage_root/System/Userland/network" \
        "$stage_root/System/Userland/security" \
        "$stage_root/System/Userland/updates" \
        "$stage_root/System/Userland/system"

    python3 - "$stage_root" <<'PY'
import pathlib
import sqlite3
import sys

root = pathlib.Path(sys.argv[1])

def write_config(path, rows, user_version):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE setting(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.executemany("INSERT INTO setting(key, value) VALUES (?, ?)", rows)
    db.execute(f"PRAGMA user_version={user_version}")
    db.commit()
    db.execute("VACUUM")
    db.close()

write_config(
    root / "System/Configuration/System/System.config",
    [
        ("core.version", "0.8"),
        ("core.name", "CoreV09"),
        ("ui.status", "pending"),
        ("system.status.command", "/System/Userland/system status"),
        ("network.status.command", "/System/Userland/network status"),
        ("security.status.command", "/System/Userland/security status"),
        ("updates.status.command", "/System/Userland/updates status"),
        ("v1.readiness", "foundation-without-ui"),
    ],
    9,
)

write_config(
    root / "System/Configuration/Updates/Updates.config",
    [
        ("updates.status", "Unknown"),
        ("kernel.source", "/System/Kernel/Linux/RT"),
        ("userland.source", "OpenBSD-first source manifest"),
        ("userland.fallback", "FreeBSD source manifest"),
        ("shell.source", "zsh upstream"),
        ("runtime.source", "AILang/Mixtar runtime"),
        ("policy", "check-only-until-certified-build-exists"),
    ],
    1,
)
PY

    note "installed CoreV09 system status foundation"
}
build_console_setup() {
    source_file="$script_dir/../initramfs/mixtar_console_setup.c"
    output_file="$stage_root/System/Init/ConsoleSetup"
    [ -f "$source_file" ] || fail "missing ConsoleSetup source: $source_file"
    if command -v musl-gcc >/dev/null 2>&1; then
        console_cc=musl-gcc
    else
        console_cc=${CC:-cc}
    fi
    "$console_cc" -std=c11 -O2 -static -Wall -Wextra -Werror \
        "$source_file" -o "$output_file"
    chmod 0755 "$output_file"
    note "built native ConsoleSetup"
}

write_global_zsh_startup() {
    mkdir -p "$stage_root/System/Shells"
    cat > "$stage_root/System/Shells/zshenv" <<'EOF'
export PATH="/System/Shells:/System/Userland"
export LD_LIBRARY_PATH="/System/Shells/Runtime"
export TERMINFO="/System/Shells/Terminfo"
export TERM="${TERM:-linux}"
export LANG="${LANG:-C.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-C.UTF-8}"
export MIXTAR_SYSTEM_NAME="${MIXTAR_SYSTEM_NAME:-MixtarRVS}"
if [[ -o interactive && -r /System/Shells/zshrc ]]; then
    source /System/Shells/zshrc
fi
EOF
    cat > "$stage_root/System/Shells/zshrc" <<'EOF'
if [[ -n ${MIXTAR_GLOBAL_ZSHRC_LOADED:-} ]]; then
    return
fi
typeset -g MIXTAR_GLOBAL_ZSHRC_LOADED=1
bindkey -e
KEYTIMEOUT=5
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey '^[[3~' delete-char
bindkey '^[[A' up-line-or-history
bindkey '^[[B' down-line-or-history
bindkey '^[[C' forward-char
bindkey '^[[D' backward-char
bindkey '^[OA' up-line-or-history
bindkey '^[OB' down-line-or-history
bindkey '^[OC' forward-char
bindkey '^[OD' backward-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[OF' end-of-line
mixtar-ignore-function-key() { zle redisplay }
zle -N mixtar-ignore-function-key
for mixtar_key in \
    $'\e[[A' $'\e[[B' $'\e[[C' $'\e[[D' $'\e[[E' \
    $'\eOP' $'\eOQ' $'\eOR' $'\eOS' \
    $'\e[11~' $'\e[12~' $'\e[13~' $'\e[14~' $'\e[15~' \
    $'\e[17~' $'\e[18~' $'\e[19~' $'\e[20~' $'\e[21~' \
    $'\e[23~' $'\e[24~'
do
    bindkey "$mixtar_key" mixtar-ignore-function-key
done
unset mixtar_key
setopt PROMPT_SUBST
PROMPT='%F{green}${USER:-User}@${MIXTAR_SYSTEM_NAME}%f:%~> '
EOF
    chmod 0644 "$stage_root/System/Shells/zshenv" "$stage_root/System/Shells/zshrc"
    note "installed immutable global ZSH startup"
}

augment_console_configuration() {
    STAGE_ROOT="$stage_root" python3 - <<'PY'
import os
import pathlib
import sqlite3

root = pathlib.Path(os.environ["STAGE_ROOT"])

def update_key_value_db(path, entries, version):
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    try:
        tables = [row[0] for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )]
        selected = None
        for preferred in ("meta", "metadata", "setting", "settings"):
            if preferred in tables:
                columns = {row[1] for row in connection.execute(
                    f'PRAGMA table_info("{preferred}")'
                )}
                if {"key", "value"}.issubset(columns):
                    selected = preferred
                    break
        if selected is None and not tables:
            connection.execute(
                "CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)"
            )
            selected = "settings"
        if selected is None:
            raise RuntimeError(f"no key/value table in {path}")
        connection.executemany(
            f'INSERT OR REPLACE INTO "{selected}" (key, value) VALUES (?, ?)',
            entries,
        )
        connection.execute(f"PRAGMA user_version={version}")
        connection.commit()
    finally:
        connection.close()

update_key_value_db(
    root / "System/Configuration/MixtarRVS.config",
    [
        ("console.setup", "/System/Init/ConsoleSetup"),
        ("console.keymap", "pl"),
        ("locale.name", "C.UTF-8"),
        ("persistence.device.wait.ms", "5000"),
    ],
    9,
)
update_key_value_db(
    root / "System/Configuration/ZSH/ZSH.config",
    [
        ("startup.global", "/System/Shells/zshenv"),
        ("startup.interactive", "/System/Shells/zshrc"),
        ("locale", "C.UTF-8"),
        ("keyboard.layout", "pl"),
    ],
    6,
)
PY
    note "recorded console, locale and global ZSH policy"
}

stage() {
    require_safe_generated_path "$stage_root"
    require_safe_generated_path "$efi_stage"

    rm -rf "$stage_root" "$efi_stage"
    stage_layout
    write_pid1_config
    write_security_config
    write_admin_command_stubs
    write_networking_config
    write_config_seed
    write_contract_marker
    write_kernel_profile
    write_driver_store
    stage_existing_artifacts
    build_console_setup
    write_global_zsh_startup
    augment_console_configuration
    note "staged CoreV09 root at $stage_root"
    note "staged CoreV09 EFI mirror at $efi_stage"
}

cmd="stage"
while [ $# -gt 0 ]; do
    case "$1" in
        plan|stage|verify)
            cmd=$1
            shift
            ;;
        --root)
            [ $# -ge 2 ] || fail "missing --root value"
            stage_root=$2
            shift 2
            ;;
        --efi-stage)
            [ $# -ge 2 ] || fail "missing --efi-stage value"
            efi_stage=$2
            shift 2
            ;;
        --efi-source)
            [ $# -ge 2 ] || fail "missing --efi-source value"
            efi_source=$2
            explicit_efi_source=1
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

case "$cmd" in
    plan)
        plan
        ;;
    stage)
        stage
        ;;
    verify)
        sh "$script_dir/keyboard-verify.sh" --root "$stage_root"
        exec "$script_dir/corev09-verify.sh" --root "$stage_root" --efi-stage "$efi_stage"
        ;;
esac
