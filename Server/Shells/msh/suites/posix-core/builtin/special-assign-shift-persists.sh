# msh-name: assignment before shift persists while shift mutates positionals
# msh-profile: posix
set -- first second
A=one shift
printf '<%s/%s/%s>\n' "$A" "$1" "$#"
