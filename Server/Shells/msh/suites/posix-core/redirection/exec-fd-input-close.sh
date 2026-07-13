# msh-category: redirection
# msh-name: exec arbitrary fd input close
printf 'a\n' > in.txt
exec 3<in.txt
exec 3<&-
read x <&3
printf 's=%s x=<%s>\n' "$?" "$x"
