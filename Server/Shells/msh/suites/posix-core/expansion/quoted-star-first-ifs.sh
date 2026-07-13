# msh-name: quoted star first IFS
# msh-profile: posix
set -- a b; IFS=,; printf "$*"
