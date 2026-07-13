#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../../.." && pwd)"
cd "$repo_root"

wrap="$repo_root/out/musl-cc-wrapper"
mkdir -p "$wrap/lib" "$wrap/build" "$repo_root/out/mixtarrvs-musl"

python3 - <<'PY'
from pathlib import Path
import re

src = Path("Server/Userland/Toolkit/OpenBSD/src/lib/libc/gen/fts.c")
out = Path("out/musl-cc-wrapper/build/fts_musl.c")
text = src.read_text()
text = text.replace(
    "#include <unistd.h>\n",
    "#include <unistd.h>\n"
    "#include <stdint.h>\n"
    "#include <stddef.h>\n"
    "#ifndef DEF_WEAK\n#define DEF_WEAK(x)\n#endif\n"
    "#ifndef FTS_MAXLEVEL\n#define FTS_MAXLEVEL INT_MAX\n#endif\n",
)
text = text.replace("dp->d_namlen", "strlen(dp->d_name)")
text = text.replace("ALIGNBYTES", "(sizeof(max_align_t) - 1)")
text = text.replace(
    "(struct stat *)ALIGN(p->fts_name + namelen + 2)",
    "(struct stat *)(((uintptr_t)(p->fts_name + namelen + 2) + "
    "sizeof(max_align_t) - 1) & ~(uintptr_t)(sizeof(max_align_t) - 1))",
)
text = text.replace(
    "qsort(sp->fts_array, nitems, sizeof(FTSENT *), sp->fts_compar);",
    "qsort(sp->fts_array, nitems, sizeof(FTSENT *), "
    "(int (*)(const void *, const void *))sp->fts_compar);",
)
text = re.sub(
    r"p = recallocarray\(sp->fts_path, sp->fts_pathlen,\s*"
    r"sp->fts_pathlen \+ more, 1\);",
    "p = reallocarray(sp->fts_path, sp->fts_pathlen + more, 1);",
    text,
)
out.write_text(text)
PY

musl-gcc -static -O2 -D_GNU_SOURCE -D_DEFAULT_SOURCE \
  -c "$wrap/build/fts_musl.c" \
  -o "$wrap/build/fts.o"
ar rcs "$wrap/lib/libfts.a" "$wrap/build/fts.o"

cat > "$wrap/cc" <<'SH'
#!/usr/bin/env bash
wrap_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec musl-gcc -static -L"$wrap_dir/lib" "$@"
SH
chmod +x "$wrap/cc"

python3 Server/Userland/Toolkit/Bridge/scripts/mixtarrvs_musl_toolkit.py package all >/dev/null
python3 - <<'PY'
from pathlib import Path

src = Path("out/mixtarrvs-musl/build-mixtarrvs-musl.sh")
dst = Path("out/mixtarrvs-musl/build-mixtarrvs-musl-keepgoing.sh")
text = src.read_text()
text = text.replace("set -eu", "set -u")
text = text.replace("; exit 1; }", "; true; }")
dst.write_text(text)
PY

rm -rf out/mixtarrvs-musl-target
PATH="$wrap:$PATH" sh out/mixtarrvs-musl/build-mixtarrvs-musl-keepgoing.sh \
  | tee out/mixtarrvs-musl-target-build.log

find out/mixtarrvs-musl-target/bin -maxdepth 1 -type f -executable -printf "%f\n" \
  | sort > out/mixtarrvs-musl-target/BUILT
grep "^FAIL " out/mixtarrvs-musl-target-build.log | awk "{print \$2}" \
  > out/mixtarrvs-musl-target/FAILED || true

printf "built_count="
wc -l < out/mixtarrvs-musl-target/BUILT | tr -d " "
printf "\nfailed_tools="
tr "\n" " " < out/mixtarrvs-musl-target/FAILED
printf "\n"
