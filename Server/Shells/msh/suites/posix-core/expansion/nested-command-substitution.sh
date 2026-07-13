# msh-name: nested command substitution
# msh-profile: posix
A=$(printf $(printf ok)); printf $A
