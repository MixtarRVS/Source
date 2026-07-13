# msh-category: expansion
# msh-name: empty quoted at produces no fields
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set --
for x in "$@"; do
    printf X
done
printf '<%s>\n' "$#"
