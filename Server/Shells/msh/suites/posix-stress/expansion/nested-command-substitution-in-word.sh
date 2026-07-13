# msh-category: expansion
# msh-name: nested command substitution in word
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '<%s>\n' "a$(printf b$(printf c))d"
