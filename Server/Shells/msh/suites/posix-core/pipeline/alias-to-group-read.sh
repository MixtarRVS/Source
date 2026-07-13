# msh-category: pipeline
# msh-name: alias to group read
alias ll='ls -l'
alias | { read A; printf '<%s>\n' "$A"; }
