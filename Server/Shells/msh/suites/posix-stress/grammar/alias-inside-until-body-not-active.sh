# msh-category: grammar
# msh-name: alias inside until body not active
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
until false; do
    alias hi='printf ok'
    hi
    break
done
