# msh-category: grammar
# msh-name: subshell redirection preserves parent state
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=outer
( X=inner; printf "$X" > out )
printf '<%s:' "$X"
read Y < out
printf '%s>\n' "$Y"
