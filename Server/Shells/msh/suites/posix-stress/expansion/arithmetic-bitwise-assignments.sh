# msh-category: expansion
# msh-name: arithmetic bitwise assignments
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=7
B=7
C=4
printf '<%s:%s:%s:%s:%s:%s>\n' "$((A&=3))" "$A" "$((B^=3))" "$B" "$((C|=1))" "$C"
