# msh-name: exec stdout survives command-local read redirection
# msh-profile: posix
exec >out
printf '%s\n' one
read X < out
printf '%s\n' "$X"
