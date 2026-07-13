# msh-name: ifs non-whitespace
# msh-profile: posix
IFS=,; set -- a,b,,c; printf [$1][$2][$3][$4]
