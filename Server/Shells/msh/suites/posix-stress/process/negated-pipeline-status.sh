# msh-category: process
# msh-name: negated pipeline status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
! false | true
printf '<%s>\n' "$?"
