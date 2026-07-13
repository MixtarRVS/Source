# msh-category: redirection
# msh-name: function exec fd open persists
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { exec 8>out; }
f
printf A >&8
exec 8>&-
read X < out
printf '<%s>\n' "$X"
