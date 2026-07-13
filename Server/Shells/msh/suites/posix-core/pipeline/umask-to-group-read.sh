# msh-category: pipeline
# msh-name: umask to group read
umask | { read A; printf '<%s>\n' "$A"; }
