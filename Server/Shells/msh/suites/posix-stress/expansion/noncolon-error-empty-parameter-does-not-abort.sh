# msh-category: expansion
# msh-name: noncolon error empty parameter does not abort
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=
printf '<%s>\n' "${A?empty}"
