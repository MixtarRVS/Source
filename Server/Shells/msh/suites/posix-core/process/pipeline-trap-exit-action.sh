# msh-category: process
# msh-name: pipeline exit trap action
trap 'printf hi' EXIT
trap | { read A; printf '<%s>\n' "$A"; }
