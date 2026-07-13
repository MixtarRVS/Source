# msh-category: builtin
# msh-name: dot return status
printf 'return 5\n' > dot-return-script
. ./dot-return-script
printf $?
