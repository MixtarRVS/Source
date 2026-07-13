# msh-category: builtin
# msh-name: command p V sh default path
PATH=.
command -p -V sh
printf 's=%s\n' "$?"
