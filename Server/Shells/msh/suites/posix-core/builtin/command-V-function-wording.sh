# msh-name: command V function wording
f() { :; }
command -V f
command -V :
command -V true
printf 'S:%s\n' $?
