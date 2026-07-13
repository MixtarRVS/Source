# msh-name: assignment before set persists while set mutates positionals
# msh-profile: posix
A=one set -- arg
printf '<%s/%s/%s>\n' "$A" "$1" "$#"
