# msh-name: printf read pipeline
# msh-profile: posix
printf 'ok\n' | read A; printf ${A-unset}
