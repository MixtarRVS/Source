# msh-category: redirection
# msh-name: input duplicate shared offset
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'one\ntwo\n' > in
exec 8<in
exec 9<&8
read A <&8
read B <&9
printf '<%s><%s>\n' "$A" "$B"
