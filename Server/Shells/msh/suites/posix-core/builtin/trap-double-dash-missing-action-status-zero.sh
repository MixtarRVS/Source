# msh-category: builtin
# msh-name: trap double dash missing action status zero
trap -- TERM
printf '<%s>' "$?"