# msh-category: builtin
# msh-name: set plus o allexport disables export
# msh-profile: posix
set -o allexport
A=1
set +o allexport
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
