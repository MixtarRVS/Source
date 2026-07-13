# msh-name: set noglob
# msh-profile: posix
printf x > glob-a; set -f; set -- glob-*; printf $1
