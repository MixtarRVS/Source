# msh-category: pipeline
# msh-name: function umask to group read
f(){ umask; }
f | { read A; printf '<%s>\n' "$A"; }
