# msh-category: builtin
# msh-name: dot return exposes status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'A=ok\nreturn 7\n' > src
. ./src
printf '<%s:%s>\n' "$A" "$?"
