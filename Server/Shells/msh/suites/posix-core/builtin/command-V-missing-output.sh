# msh-name: command V missing output
command -V definitely_missing_command
printf 'S:%s\n' $?
