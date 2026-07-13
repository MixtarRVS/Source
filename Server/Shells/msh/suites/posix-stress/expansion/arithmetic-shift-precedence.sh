# msh-category: expansion
# msh-name: arithmetic shift precedence
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '<%s:%s>\n' "$((1+2<<2))" "$((8>>1+1))"
