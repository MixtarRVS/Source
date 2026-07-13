# msh-category: builtin
# msh-name: command set plus allexport keeps option side effect
# msh-profile: posix
set -a
command set +a
A=1
case "$(export -p)" in
    *"export A='1'"*) printf yes;;
    *) printf no;;
esac
printf ':%s\n' "$-"
