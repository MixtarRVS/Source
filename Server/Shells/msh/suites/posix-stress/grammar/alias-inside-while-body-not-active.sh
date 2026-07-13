# msh-category: grammar
# msh-name: alias inside while body not active
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
while true; do
    alias hi='printf ok'
    hi
    break
done
