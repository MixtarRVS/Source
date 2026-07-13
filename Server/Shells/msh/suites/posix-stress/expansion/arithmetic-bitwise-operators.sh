# msh-category: expansion
# msh-name: arithmetic bitwise operators
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '<%s:%s:%s>\n' "$((7&3))" "$((4|1))" "$((7^3))"
