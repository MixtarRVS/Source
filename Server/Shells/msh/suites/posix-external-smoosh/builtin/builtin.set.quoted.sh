# msh-source: smoosh/tests/shell/builtin.set.quoted.test
# msh-profile: posix
# msh-run: eval
myvar='a b c'
set >all
while IFS= read -r line; do
  case $line in
    myvar=*) printf '%s\n' "$line" >scr ;;
  esac
done <all
. ./scr
printf '%s\n' $myvar
