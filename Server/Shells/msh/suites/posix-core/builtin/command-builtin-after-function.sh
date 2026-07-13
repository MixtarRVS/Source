# msh-profile: posix
cd() { printf 'function-cd\n'; }
command cd .
printf 'after\n'
cd .