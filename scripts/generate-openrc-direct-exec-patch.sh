#!/usr/bin/env bash
set -euo pipefail

readonly OPENRC_COMMIT="a63d68f5c1e250ebdf9ff2c848add4dcba430ea2"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MIRROR="${XDG_CACHE_HOME:-$HOME/.cache}/mixtar/openrc/upstream.git"
WORK="${XDG_CACHE_HOME:-$HOME/.cache}/mixtar/openrc-direct-exec-patch"
TREE="$WORK/tree"
TRANSFORM="$WORK/transform.awk"
PATCH="$REPOSITORY/Patches/OpenRC/0002-direct-gendep-exec.patch"

case "$WORK" in
	/home/*/.cache/mixtar/openrc-direct-exec-patch) ;;
	*)
		printf 'Refusing unsafe patch work directory: %s\n' "$WORK" >&2
		exit 2
		;;
esac

git --git-dir="$MIRROR" cat-file -e "$OPENRC_COMMIT^{commit}"
rm -rf -- "$WORK"
mkdir -p "$TREE"
git --git-dir="$MIRROR" archive "$OPENRC_COMMIT" src/librc/librc-depend.c \
	| tar -x -C "$TREE"

git -C "$TREE" init -q
git -C "$TREE" config user.name Mixtar
git -C "$TREE" config user.email builder@mixtar.invalid
git -C "$TREE" add src/librc/librc-depend.c
git -C "$TREE" commit -qm base

cat >"$TRANSFORM" <<'AWK'
{
	line = $0
	sub(/\r$/, "", line)

	if (line == "#include <sys/stat.h>") {
		print line
		print "#include <sys/wait.h>"
		next
	}

	if (line == "static const char *bootlevel = NULL;") {
		print line
		print ""
		print "static FILE *"
		print "gendep_open(pid_t *pid)"
		print "{"
		print "\tint fds[2];"
		print "\tFILE *fp;"
		print "\tint serrno;"
		print ""
		print "\tif (pipe(fds) == -1)"
		print "\t\treturn NULL;"
		print ""
		print "\t*pid = fork();"
		print "\tif (*pid == -1) {"
		print "\t\tserrno = errno;"
		print "\t\tclose(fds[0]);"
		print "\t\tclose(fds[1]);"
		print "\t\terrno = serrno;"
		print "\t\treturn NULL;"
		print "\t}"
		print "\tif (*pid == 0) {"
		print "\t\tclose(fds[0]);"
		print "\t\tif (fds[1] != STDOUT_FILENO) {"
		print "\t\t\tif (dup2(fds[1], STDOUT_FILENO) == -1)"
		print "\t\t\t\t_exit(127);"
		print "\t\t\tclose(fds[1]);"
		print "\t\t}"
		print "\t\texecl(GENDEP, GENDEP, (char *)NULL);"
		print "\t\t_exit(127);"
		print "\t}"
		print ""
		print "\tclose(fds[1]);"
		print "\tfp = fdopen(fds[0], \"r\");"
		print "\tif (!fp) {"
		print "\t\tserrno = errno;"
		print "\t\tclose(fds[0]);"
		print "\t\twhile (waitpid(*pid, NULL, 0) == -1 && errno == EINTR)"
		print "\t\t\t;"
		print "\t\terrno = serrno;"
		print "\t}"
		print "\treturn fp;"
		print "}"
		print ""
		print "static bool"
		print "gendep_close(FILE *fp, pid_t pid)"
		print "{"
		print "\tint status;"
		print "\tbool ok;"
		print ""
		print "\tok = fclose(fp) == 0;"
		print "\twhile (waitpid(pid, &status, 0) == -1) {"
		print "\t\tif (errno != EINTR)"
		print "\t\t\treturn false;"
		print "\t}"
		print "\treturn ok && WIFEXITED(status) && WEXITSTATUS(status) == 0;"
		print "}"
		next
	}

	if (line == "\tbool retval = true;") {
		print line
		print "\tpid_t gendep_pid;"
		next
	}

	if (line == "\tif (!(fp = popen(GENDEP, \"r\")))") {
		print "\tif (!(fp = gendep_open(&gendep_pid)))"
		next
	}

	if (line == "\tpclose(fp);") {
		print "\tif (!gendep_close(fp, gendep_pid)) {"
		print "\t\trc_stringlist_free(config);"
		print "\t\trc_deptree_free(deptree);"
		print "\t\treturn false;"
		print "\t}"
		next
	}

	print line
}
AWK

awk -f "$TRANSFORM" "$TREE/src/librc/librc-depend.c" \
	>"$TREE/src/librc/librc-depend.c.new"
mv "$TREE/src/librc/librc-depend.c.new" "$TREE/src/librc/librc-depend.c"

git -C "$TREE" diff --check
git -C "$TREE" diff --src-prefix=a/ --dst-prefix=b/ \
	-- src/librc/librc-depend.c >"$PATCH"
git -C "$TREE" restore src/librc/librc-depend.c
git -C "$TREE" apply --check "$PATCH"
printf '%s\n' "$PATCH"
