# msh-profile: posix
set -- -b
while getopts ':b:' opt; do
  printf '<%s:%s:%s>\n' "$opt" "${OPTARG-}" "$OPTIND"
done
printf 'done:%s\n' "$OPTIND"