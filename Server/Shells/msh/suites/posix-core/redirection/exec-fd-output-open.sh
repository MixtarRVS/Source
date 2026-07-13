# msh-category: redirection
# msh-name: exec arbitrary fd output open
exec 3>fdopen.out
printf x >&3
read got < fdopen.out
printf 'got=<%s>\n' "$got"
