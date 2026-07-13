# msh-category: builtin
# msh-name: set allexport exports assignment
set -a
A=1
case "$(export -p)" in
    *"export A='1'"*) printf yes;;
    *) printf no;;
esac
case "$-" in
    *a*) printf ':flag';;
    *) printf ':noflag';;
esac
printf ':s=%s\n' "$?"
