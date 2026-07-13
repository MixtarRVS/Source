# msh-category: grammar
# msh-name: nested function definition execution
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { g() { printf inner; }; g; }
f
