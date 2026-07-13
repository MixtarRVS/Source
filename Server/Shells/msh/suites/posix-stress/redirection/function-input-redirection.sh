# msh-category: redirection
# msh-name: function input redirection
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'word\n' > in
f() { read X; printf '<%s>\n' "$X"; }
f < in
