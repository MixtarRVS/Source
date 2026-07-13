# msh-category: builtin
# msh-name: set o allexport exports assignment
set -o allexport
A=1
case "$(export -p)" in
    *"export A='1'"*) printf yes;;
    *) printf no;;
esac
printf ':s=%s\n' "$?"
