# msh-category: builtin
# msh-name: set plus o noglob reenables pathname expansion
# msh-profile: posix
printf x > set-plus-o-noglob-a.txt
printf x > set-plus-o-noglob-b.txt
set -o noglob
printf 'off:<%s>\n' set-plus-o-noglob-*.txt
set +o noglob
printf 'on:<%s>\n' set-plus-o-noglob-*.txt
