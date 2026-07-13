# msh-category: builtin
# msh-name: dot source searches current directory when PATH unset
# msh-profile: extension
printf 'VALUE=ok\n' > file
unset PATH
. file
printf '%s\n' "$VALUE"
