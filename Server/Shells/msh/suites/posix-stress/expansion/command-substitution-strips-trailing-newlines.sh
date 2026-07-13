# msh-category: expansion
# msh-name: command substitution strips trailing newlines
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf 'a\n\n')
printf '<%s>\n' "$X"
