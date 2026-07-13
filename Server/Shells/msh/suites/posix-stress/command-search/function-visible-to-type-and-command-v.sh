# msh-category: command-search
# msh-name: function visible to type and command v
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { :; }
type f
command -v f
