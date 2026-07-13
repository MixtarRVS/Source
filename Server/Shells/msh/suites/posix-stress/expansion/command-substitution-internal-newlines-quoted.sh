# msh-category: expansion
# msh-name: command substitution internal newlines quoted
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf 'a\nb\n')
printf '<%s>\n' "$X"
