# msh-category: expansion
# msh-name: arithmetic command substitution keeps expression text
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '<%s>\n' "$(( $(printf 1+2) * 2 ))"
