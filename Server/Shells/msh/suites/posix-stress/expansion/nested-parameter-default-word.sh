# msh-category: expansion
# msh-name: nested parameter default word
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
unset A B
printf '<%s>\n' "${A:-${B:-x}}"
