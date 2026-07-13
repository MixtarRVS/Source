# msh-category: redirection
# msh-name: exec persistent stdout captures export output
exec 3>&1
export MSH_FD_EXPORT=ok
exec >out
export -p
exec >&3
exec 3>&-
while IFS= read -r line; do
    case $line in
        *MSH_FD_EXPORT*) printf '%s' "$line" ;;
    esac
done < out
