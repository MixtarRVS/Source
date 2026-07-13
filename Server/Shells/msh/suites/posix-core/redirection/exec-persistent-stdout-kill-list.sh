# msh-category: redirection
# msh-name: exec persistent stdout captures kill list output
exec 3>&1
exec >out
kill -l 1
exec >&3
exec 3>&-
read A < out
printf '%s' "$A"
