# msh-category: command-search
# msh-name: command suppresses alias execution
# msh-stderr: normalized
alias aa='printf alias'
command aa
printf '<%s>\n' "$?"
