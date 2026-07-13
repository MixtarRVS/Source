# msh-category: grammar
# msh-name: for no in iterates positionals
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- a b
for x do
    printf '<%s>' "$x"
done
printf '\n'
