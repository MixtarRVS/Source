# msh-category: pipeline
# msh-name: group umask to group read
{ umask; } | { read A; printf '<%s>\n' "$A"; }
