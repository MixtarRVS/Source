# msh-name: arithmetic logical
# msh-profile: posix
printf $((1 && 2)):$((0 || 4)):$((!0)):$((!5))
