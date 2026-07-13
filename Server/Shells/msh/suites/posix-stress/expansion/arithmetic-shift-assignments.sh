# msh-category: expansion
# msh-name: arithmetic shift assignments
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=1
B=16
printf '<%s:%s:%s:%s>\n' "$((A<<=3))" "$A" "$((B>>=2))" "$B"
