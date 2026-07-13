# msh-category: builtin
# msh-name: read raw with option delimiter
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'a\\b\n' > in
read -r -- X < in
printf '<%s>\n' "$X"
