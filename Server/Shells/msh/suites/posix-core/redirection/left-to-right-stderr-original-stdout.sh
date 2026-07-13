# msh-category: redirection
# msh-name: left to right stderr original stdout
{ printf out; printf err >&2; } 2>&1 > out-file
read A < out-file
printf ":$A:"
