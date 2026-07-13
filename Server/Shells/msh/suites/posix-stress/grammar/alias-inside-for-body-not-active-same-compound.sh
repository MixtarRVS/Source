# msh-category: grammar
# msh-name: alias inside for body not active same compound
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
for x in 1; do
    alias hi='printf ok'
    hi
done
