# msh-name: single quoted literal double quote and dollar
# msh-profile: posix
X=bad
printf '%s\n' 'a "$X"'
