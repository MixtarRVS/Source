# msh-category: process
# msh-name: pipeline trap action list reset
trap 'printf hi' TERM
trap | { read A; printf '<%s>\n' "$A"; }
