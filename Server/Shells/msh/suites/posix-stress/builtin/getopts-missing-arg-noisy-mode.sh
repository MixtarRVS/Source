# msh-category: builtin
# msh-name: getopts missing arg noisy mode
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
set -- -a
while getopts a: opt; do
    printf '<%s:%s>' "$opt" "$OPTARG"
done
printf '<%s>\n' "$OPTIND"
