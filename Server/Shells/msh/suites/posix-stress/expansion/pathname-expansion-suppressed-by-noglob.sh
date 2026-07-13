# msh-category: expansion
# msh-name: pathname expansion suppressed by noglob
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
> ga
> gb
set -f
for x in g?; do
    printf '<%s>' "$x"
done
printf '\n'
