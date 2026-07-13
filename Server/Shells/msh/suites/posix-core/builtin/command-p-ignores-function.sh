# msh-profile: posix
cd() { printf 'function-cd\n'; }
command -p cd .
printf 'after\n'
cd .