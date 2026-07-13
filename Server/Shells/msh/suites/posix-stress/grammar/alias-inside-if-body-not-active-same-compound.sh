# msh-category: grammar
# msh-name: alias inside if body not active same compound
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
if true; then
    alias hi='printf ok'
    hi
fi
