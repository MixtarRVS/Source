# msh-category: process
# msh-name: exit trap preserves last status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'printf "<%s>\n" "$?"' EXIT
false
