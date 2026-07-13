# msh-category: grammar
# msh-name: alias in function body defined inside function not active
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
f() { alias hi='printf ok'; hi; }
f
