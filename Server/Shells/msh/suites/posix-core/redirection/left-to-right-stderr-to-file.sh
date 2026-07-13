# msh-category: redirection
# msh-name: left to right stderr to file
{ printf out; printf err >&2; } > both-file 2>&1
read A < both-file
printf "$A"
