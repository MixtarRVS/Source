# msh-category: expansion
# msh-name: arithmetic shift operators
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '<%s:%s>\n' "$((1<<3))" "$((16>>2))"
