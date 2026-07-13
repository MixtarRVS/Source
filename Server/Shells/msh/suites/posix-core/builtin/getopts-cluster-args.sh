# msh-profile: posix
set -- -ab value rest
while getopts 'ab:' opt; do
  printf '<%s:%s:%s>\n' "$opt" "${OPTARG-}" "$OPTIND"
done
printf 'done:%s\n' "$OPTIND"