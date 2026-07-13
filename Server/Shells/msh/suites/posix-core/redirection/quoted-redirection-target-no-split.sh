# msh-category: redirection
# msh-name: quoted redirection target no split
A='x y'
printf ok > "$A"
read B < "$A"
printf "$B"
