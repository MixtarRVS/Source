# msh-name: quoted at standalone
# msh-profile: posix
set -- a b; for x in "$@"; do printf [$x]; done
