# msh-category: grammar
# msh-name: function return in conditional
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { return 4; }
if f; then
    printf bad
else
    printf '<%s>\n' "$?"
fi
