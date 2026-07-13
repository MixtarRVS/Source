# msh-name: shift
# msh-profile: posix
set -- a b c; shift 2; printf $1:$#
