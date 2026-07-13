# msh-run: file
# msh-args: one "two words" ""
printf '<%s>\n' "$#"
for x in "$@"; do printf '[%s]\n' "$x"; done
