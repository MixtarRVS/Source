# msh-category: redirection
# msh-name: bad output fd redirection-only status
# msh-stderr: normalized
3>&9
printf 's=%s\n' "$?"
