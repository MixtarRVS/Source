# msh-category: grammar
# msh-name: function call redirection
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { printf A; }
f > out
read X < out
printf '<%s>\n' "$X"
