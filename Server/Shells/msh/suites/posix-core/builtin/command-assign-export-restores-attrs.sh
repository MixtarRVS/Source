# msh-category: builtin
# msh-name: command assignment export restores attributes
A=outer
A=inner command export A
printf '<%s>\n' "$A"
case "$(export -p)" in
    *"export A="*) printf 'exported\n' ;;
    *) printf 'not-exported\n' ;;
esac
