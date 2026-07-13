# msh-category: expansion
# msh-name: assignment command substitution status
A=$(false)
printf 's1=%s\n' "$?"
A=$(false) B=x
printf 's2=%s\n' "$?"
A=x B=$(false)
printf 's3=%s\n' "$?"
A=$(false) B=$(true)
printf 's4=%s\n' "$?"
A=$(true) B=x
printf 's5=%s\n' "$?"
