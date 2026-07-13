# msh-name: pathname basic
# msh-profile: posix
printf x > glob-a; set -- glob-*; printf $1
