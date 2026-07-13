# msh-name: pathname ASCII sort
# msh-profile: posix
printf x > sort-glob-a; printf x > sort-glob-B; printf x > sort-glob-c; set -- sort-glob-*; printf $1:$2:$3
