# msh-category: grammar
# msh-name: function with nested group and subshell
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() {
    { printf A; (printf B); printf C; }
}
f
