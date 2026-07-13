# msh-category: diagnostic
# msh-name: command eval set invalid option stderr
# msh-stderr: normalized
command eval 'set -Z'
printf 'after\n'