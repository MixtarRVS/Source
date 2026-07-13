# msh-profile: posix
printf 'VALUE=ok\n' > file
PATH=.
. file
printf '%s\n' "$VALUE"