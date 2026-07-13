# msh-category: redirection
# msh-name: brace group local input source fd retarget preserves offset
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'A\nB\n' > outer
printf 'I\n' > inner
exec 3< outer
{ read I <&3 3< inner; }
read O <&3
printf '<%s:%s>\n' "$I" "$O"
