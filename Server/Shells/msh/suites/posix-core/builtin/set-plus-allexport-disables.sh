# msh-category: builtin
# msh-name: set plus allexport disables export
set -a
A=1
set +a
B=2
case "$(export -p)" in
    *"export A='1'"*) printf A;;
    *) printf noA;;
esac
case "$(export -p)" in
    *"export B='2'"*) printf B;;
    *) printf noB;;
esac
case "$-" in
    *a*) printf ':flag';;
    *) printf ':noflag';;
esac
printf ':s=%s\n' "$?"
