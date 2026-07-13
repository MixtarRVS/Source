# msh-category: expansion
# msh-name: quoted command substitution strips only trailing newlines
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf 'a\n\nb\n\n')
printf '<%s>\n' "$X"
