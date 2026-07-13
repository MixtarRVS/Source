OPTIND=1
while getopts ab: o -a -b bee; do
  printf '<%s:%s>\n' "$o" "${OPTARG-unset}"
done
printf 'optind=%s\n' "$OPTIND"
