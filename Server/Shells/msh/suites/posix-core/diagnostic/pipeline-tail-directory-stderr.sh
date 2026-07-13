# msh-name: pipeline tail directory execution stderr
# msh-stderr: normalized
true | ./
printf '<%s>\n' "$?"
