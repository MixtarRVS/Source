# msh-category: builtin
# msh-name: command set noglob keeps option side effect
# msh-profile: posix
printf x > command-set-noglob-a.txt
printf x > command-set-noglob-b.txt
set +f
command set -f
printf '<%s>\n' command-set-noglob-*.txt
