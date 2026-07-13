# msh-name: subshell isolation
# msh-profile: posix
A=outer; (A=inner); printf $A
