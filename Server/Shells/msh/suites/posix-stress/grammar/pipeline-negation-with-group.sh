# msh-category: grammar
# msh-name: pipeline negation with group
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
! { false; } | true
printf '<%s>\n' "$?"
