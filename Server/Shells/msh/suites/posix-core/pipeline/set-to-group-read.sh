# msh-category: pipeline
# msh-name: set to group read
A=needle
set | { read A; printf '<%s>\n' "$A"; }
