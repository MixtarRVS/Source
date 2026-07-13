# msh-category: process
# msh-name: pipeline trap ignored list preserved
trap '' TERM
trap | { read A; printf '<%s>\n' "$A"; }
