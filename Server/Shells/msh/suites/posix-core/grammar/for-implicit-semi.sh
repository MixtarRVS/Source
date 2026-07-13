# msh-name: for implicit positionals semicolon
# msh-profile: posix
set -- a b; for x; do printf [$x]; done
