# msh-category: expansion
# msh-name: quoted empty parameter preserves field
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=
set -- "$A" x
printf '<%s><%s>\n' "$#" "$1"
