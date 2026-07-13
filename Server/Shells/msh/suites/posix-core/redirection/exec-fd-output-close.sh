# msh-category: redirection
# msh-name: exec arbitrary fd output close
exec 3>fdclose.out
printf x >&3
exec 3>&-
printf y >&3
printf 's=%s\n' "$?"
read got < fdclose.out
printf 'got=<%s>\n' "$got"
