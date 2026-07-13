# msh-category: redirection
# msh-name: left to right stderr joins redirected stdout
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
{ printf 'out\n'; printf 'err\n' >&2; } >out 2>&1
exec 8<out
read A <&8
read B <&8
exec 8<&-
printf '<%s><%s>\n' "$A" "$B"
