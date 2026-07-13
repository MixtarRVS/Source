# msh-category: builtin
# msh-name: getopts clustered options
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- -ab value
while getopts ab opt; do
    printf '<%s>' "$opt"
done
printf '<%s>\n' "$OPTIND"
