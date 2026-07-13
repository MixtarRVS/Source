# msh-name: invalid trap operand is nonfatal in script sequence
# msh-profile: posix
trap x BADSIG
printf '%s\n' after
