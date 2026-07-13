# msh-category: redirection
# msh-name: command local input fd
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'word\n' > in
read X <&8 8<in
printf '<%s>\n' "$X"
