# msh-name: pattern trim
# msh-profile: posix
A=abcabc; printf ${A#a*}:${A%%c}
